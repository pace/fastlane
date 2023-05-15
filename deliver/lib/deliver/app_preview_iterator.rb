module Deliver
  # This is a convinient class that enumerates app store connect's videos in various degrees.
  class AppPreviewIterator
    NUMBER_OF_THREADS = Helper.test? ? 1 : [ENV.fetch("DELIVER_NUMBER_OF_THREADS", 10).to_i, 10].min

    # @param localizations [Array<Spaceship::ConnectAPI::AppStoreVersionLocalization>]
    def initialize(localizations)
      @localizations = localizations
    end

    # Iterate app_preview_set over localizations
    #
    # @yield [localization, app_preview_set]
    # @yieldparam [optional, Spaceship::ConnectAPI::AppStoreVersionLocalization] localization
    # @yieldparam [optional, Spaceship::ConnectAPI::AppPreviewSet] app_preview_set
    def each_app_preview_set(localizations = @localizations, &block)
      return enum_for(__method__, localizations) unless block_given?

      # Collect app_screenshot_sets from localizations in parallel but
      # limit the number of threads working at a time with using `lazy` and `force` controls
      # to not attack App Store Connect
      results = localizations.each_slice(NUMBER_OF_THREADS).lazy.map do |localizations_grouped|
        localizations_grouped.map do |localization|
          Thread.new do
            [localization, localization.get_app_preview_sets]
          end
        end
      end.flat_map do |threads|
        threads.map { |t| t.join.value }
      end.force

      results.each do |localization, app_preview_sets|
        app_preview_sets.each do |app_preview_set|
          yield(localization, app_preview_set)
        end
      end
    end

    # Iterate app_preview over localizations and app_preview_sets
    #
    # @yield [localization, app_preview_set, app_preview]
    # @yieldparam [optional, Spaceship::ConnectAPI::AppStoreVersionLocalization] localization
    # @yieldparam [optional, Spaceship::ConnectAPI::AppPreviewSet] app_preview_set
    # @yieldparam [optional, Spaceship::ConnectAPI::AppPreview] app_preview
    def each_app_preview(&block)
      return enum_for(__method__) unless block_given?

      each_app_preview_set do |localization, app_preview_set|
        app_preview_set.app_previews.each do |app_preview|
          yield(localization, app_preview_set, app_preview)
        end
      end
    end

    # Iterate given local app_preview over localizations and app_preview_sets
    #
    # @param previews_per_language [Hash<String, Array<Deliver::AppPreview>]
    # @yield [localization, app_screenshot_set, app_screenshot]
    # @yieldparam [optional, Spaceship::ConnectAPI::AppStoreVersionLocalization] localization
    # @yieldparam [optional, Spaceship::ConnectAPI::AppPreviewSet] app_preview_set
    # @yieldparam [optional, Deliver::AppPreview] app_preview
    # @yieldparam [optional, Integer] index a number reperesents which position the screenshot will be
    def each_local_preview(previews_per_language, &block)
      return enum_for(__method__, screenshots_per_language) unless block_given?

      # filter unnecessary localizations
      supported_localizations = @localizations.reject { |l| previews_per_language[l.locale].nil? }

      # build a hash that can access app_screenshot_set corresponding to given locale and display_type
      # via parallelized each_app_screenshot_set to gain performance
      app_preview_set_per_locale_and_display_type = each_app_preview_set(supported_localizations)
                                                       .each_with_object({}) do |(localization, app_preview_set), hash|
        hash[localization.locale] ||= {}
        hash[localization.locale][app_preview_set.preview_type] = app_preview_set
      end

      # iterate over previews per localization
      previews_per_language.each do |language, previews_for_language|
        localization = supported_localizations.find { |l| l.locale == language }
        previews_per_display_type = previews_for_language.reject { |app_preview| app_preview.device_type.nil? }.group_by(&:device_type)

        previews_per_display_type.each do |display_type, previews|
          # create AppPreviewSet for given display_type if it doesn't exist
          app_preview_set = (app_preview_set_per_locale_and_display_type[language] || {})[display_type]
          app_preview_set ||= localization.create_app_preview_set(attributes: { previewType: display_type })

          # iterate over screenshots per display size with index
          previews.each.with_index do |preview, index|
            yield(localization, app_preview_set, preview, index)
          end
        end
      end
    end
  end
end
