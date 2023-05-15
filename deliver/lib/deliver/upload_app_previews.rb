require 'fastlane_core'
require 'spaceship/tunes/tunes'
require 'digest/md5'

require_relative 'app_preview'
require_relative 'module'
require_relative 'loader'
require_relative 'app_preview_iterator'

module Deliver
  # upload previews to App Store Connect
  class UploadPreviews
    DeletePreviewSetJob = Struct.new(:app_preview_set, :localization)
    UploadPreviewJob = Struct.new(:app_preview_set, :path)

    def upload(options, previews)
      return if options[:skip_previews]
      return if options[:edit_live]

      app = Deliver.cache[:app]

      platform = Spaceship::ConnectAPI::Platform.map(options[:platform])
      version = app.get_edit_app_store_version(platform: platform)
      UI.user_error!("Could not find a version to edit for app '#{app.name}' for '#{platform}'") unless version

      UI.important("Will begin uploading preview for '#{version.version_string}' on App Store Connect")

      UI.message("Starting with the upload of videos...")
      previews_per_language = previews.group_by(&:language)

      localizations = version.get_app_store_version_localizations

      if options[:overwrite_previews]
        delete_previews(localizations, previews_per_language)
      end

      # Finding languages to enable
      languages = previews_per_language.keys
      locales_to_enable = languages - localizations.map(&:locale)

      if locales_to_enable.count > 0
        lng_text = "language"
        lng_text += "s" if locales_to_enable.count != 1
        Helper.show_loading_indicator("Activating #{lng_text} #{locales_to_enable.join(', ')}...")

        locales_to_enable.each do |locale|
          version.create_app_store_version_localization(attributes: {
            locale: locale
          })
        end

        Helper.hide_loading_indicator

        # Refresh version localizations
        localizations = version.get_app_store_version_localizations
      end

      upload_previews(localizations, previews_per_language)

      Helper.show_loading_indicator("Sorting previews uploaded...")
      sort_previews(localizations)
      Helper.hide_loading_indicator

      UI.success("Successfully uploaded previews to App Store Connect")
    end

    def delete_previews(localizations, previews_per_language, tries: 5)
      tries -= 1

      worker = FastlaneCore::QueueWorker.new do |job|
        start_time = Time.now
        target = "#{job.localization.locale} #{job.app_preview_set.preview_type}"
        begin
          UI.verbose("Deleting '#{target}'")
          job.app_preview_set.delete!
          UI.message("Deleted '#{target}' -  (#{Time.now - start_time} secs)")
        rescue => error
          UI.error("Failed to delete preview #{target} - (#{Time.now - start_time} secs)")
          UI.error(error.message)
        end
      end

      iterator = AppPreviewIterator.new(localizations)
      iterator.each_app_preview_set do |localization, app_preview_set|
        # Only delete previews if trying to upload
        next unless previews_per_language.keys.include?(localization.locale)

        UI.verbose("Queued delete preview set job for #{localization.locale} #{app_preview_set.preview_type}")
        worker.enqueue(DeletePreviewSetJob.new(app_preview_set, localization))
      end

      worker.start

      # Verify all previews have been deleted
      count = iterator.each_app_preview_set.map { |_, app_preview_set| app_preview_set }
                      .reduce(0) { |sum, app_preview_set| sum + app_preview_set.app_previews.size }

      UI.important("Number of previews not deleted: #{count}")
      if count > 0
        if tries.zero?
          UI.user_error!("Failed verification of all previews deleted... #{count} preview(s) still exist")
        else
          UI.error("Failed to delete all previews... Tries remaining: #{tries}")
          delete_previews(localizations, previews_per_language, tries: tries)
        end
      else
        UI.message("Successfully deleted all previews")
      end
    end

    def upload_previews(localizations, previews_per_language, tries: 5)
      tries -= 1

      # Upload previews
      worker = FastlaneCore::QueueWorker.new do |job|
        begin
          UI.verbose("Uploading '#{job.path}'...")
          start_time = Time.now
          job.app_preview_set.upload_preview(path: job.path, wait_for_processing: false)
          UI.message("Uploaded '#{job.path}'... (#{Time.now - start_time} secs)")
        rescue => error
          UI.error(error)
        end
      end

      # Each app_preview_set can have only 3 images
      number_of_previews_per_set = {}
      total_number_of_previews = 0

      iterator = AppPreviewIterator.new(localizations)
      iterator.each_local_preview(previews_per_language) do |localization, app_preview_set, preview|
        # Initialize counter on each app preview set
        number_of_previews_per_set[app_preview_set] ||= (app_preview_set.app_previews || []).count

        if number_of_previews_per_set[app_preview_set] >= 3
          UI.error("Too many previews found for device '#{preview.device_type}' in '#{preview.language}', skipping this one (#{preview.path})")
          next
        end

        checksum = UploadPreviews.calculate_checksum(preview.path)
        duplicate = (app_preview_set.app_previews || []).any? { |s| s.source_file_checksum == checksum }

        # Enqueue uploading job if it's not duplicated otherwise preview will be skipped
        if duplicate
          UI.message("Previous uploaded. Skipping '#{preview.path}'...")
        else
          UI.verbose("Queued upload preview job for #{localization.locale} #{app_preview_set.preview_type} #{preview.path}")
          worker.enqueue(UploadPreviewJob.new(app_preview_set, preview.path))
          number_of_previews_per_set[app_preview_set] += 1
        end

        total_number_of_previews += 1
      end

      worker.start

      UI.verbose('Uploading jobs are completed')

      Helper.show_loading_indicator("Waiting for all the previews to finish being processed...")
      states = wait_for_complete(iterator)
      Helper.hide_loading_indicator
      retry_upload_previews_if_needed(iterator, states, total_number_of_previews, tries, localizations, previews_per_language)

      UI.message("Successfully uploaded all previews")
    end

    # Verify all previews have been processed
    def wait_for_complete(iterator)
      loop do
        states = iterator.each_app_preview.map { |_, _, app_preview| app_preview }.each_with_object({}) do |app_preview, hash|
          state = app_preview.asset_delivery_state['state']
          hash[state] ||= 0
          hash[state] += 1
        end

        is_processing = states.fetch('UPLOAD_COMPLETE', 0) > 0
        return states unless is_processing

        UI.verbose("There are still incomplete previews - #{states}")
        sleep(5)
      end
    end

    # Verify all previews states on App Store Connect are okay
    def retry_upload_previews_if_needed(iterator, states, tries, localizations, previews_per_language)
      is_failure = states.fetch("FAILED", 0) > 0
      is_missing_preview = !previews_per_language.empty? && !verify_local_previews_are_uploaded(iterator, previews_per_language)
      return unless is_failure || is_missing_preview

      if tries.zero?
        iterator.each_app_preview.select { |_, _, app_preview| app_preview.error? }.each do |localization, _, app_preview|
          UI.error("#{app_preview.file_name} for #{localization.locale} has error(s) - #{app_preview.error_messages.join(', ')}")
        end
        incomplete_preview_count = states.reject { |k, v| k == 'COMPLETE' }.reduce(0) { |sum, (k, v)| sum + v }
        UI.user_error!("Failed verification of all previews uploaded... #{incomplete_preview_count} incomplete preview(s) still exist")
      else
        UI.error("Failed to upload all previews... Tries remaining: #{tries}")
        # Delete bad entries before retry
        iterator.each_app_preview do |_, _, app_preview|
          app_preview.delete! unless app_preview.complete?
        end
        upload_previews(localizations, previews_per_language, tries: tries)
      end
    end

    # Return `true` if all the local previews are uploaded to App Store Connect
    def verify_local_previews_are_uploaded(iterator, previews_per_language)
      # Check if local previews' checksum exist on App Store Connect
      checksum_to_app_preview = iterator.each_app_preview.map { |_, _, app_preview| [app_preview.source_file_checksum, app_preview] }.to_h

      number_of_previews_per_set = {}
      missing_local_previews = iterator.each_local_preview(previews_per_language).select do |_, app_preview_set, local_preview|
        number_of_previews_per_set[app_preview_set] ||= (app_preview_set.app_previews || []).count
        checksum = UploadPreviews.calculate_checksum(local_preview.path)

        if checksum_to_app_preview[checksum]
          next(false)
        else
          is_missing = number_of_previews_per_set[app_preview_set] < 3 # if it's more than 3, it's skipped
          number_of_previews_per_set[app_preview_set] += 1
          next(is_missing)
        end
      end

      missing_local_previews.each do |_, _, preview|
        UI.error("#{preview.path} is missing on App Store Connect.")
      end

      missing_local_previews.empty?
    end

    def sort_previews(localizations)
      require 'naturally'
      iterator = AppPreviewIterator.new(localizations)

      # Re-order previews within app_preview_set
      worker = FastlaneCore::QueueWorker.new do |app_preview_set|
        original_ids = app_preview_set.app_previews.map(&:id)
        sorted_ids = Naturally.sort(app_preview_set.app_previews, by: :file_name).map(&:id)
        if original_ids != sorted_ids
          app_preview_set.reorder_previews(app_preview_ids: sorted_ids)
        end
      end

      iterator.each_app_preview_set do |_, app_preview_set|
        worker.enqueue(app_preview_set)
      end

      worker.start
    end

    def collect_previews(options)
      return [] if options[:skip_previews]
      return Loader.load_app_previews(options[:previews_path], options[:ignore_language_directory_validation])
    end

    # helper method so Spaceship::Tunes.client.available_languages is easier to test
    def self.available_languages
      # 2020-08-24 - Available locales are not available as an endpoint in App Store Connect
      # Update with Spaceship::Tunes.client.available_languages.sort (as long as endpoint is avilable)
      Deliver::Languages::ALL_LANGUAGES
    end

    # helper method to mock this step in tests
    def self.calculate_checksum(path)
      bytes = File.binread(path)
      Digest::MD5.hexdigest(bytes)
    end
  end
end
