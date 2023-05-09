module Deliver
  class AppPreviewValidator
    # A simple structure that holds error information as well as formatted error messages consistently
    # Set `to_skip` to `true` when just needing to skip uploading rather than causing a crash.
    class ValidationError
      # Constants that can be given to `type` param
      INVALID_FILE_EXTENSION = 'Invalid file extension'.freeze

      attr_reader :type, :path, :debug_info, :to_skip

      def initialize(type: nil, path: nil, debug_info: nil, to_skip: false)
        @type = type
        @path = path
        @debug_info = debug_info
        @to_skip = to_skip
      end

      def to_s
        "#{to_skip ? '🏃 Skipping' : '🚫 Error'}: #{path} - #{type} (#{debug_info})"
      end

      def inspect
        "\"#{type}\""
      end
    end

    ALLOWED_PREVIEW_FILE_EXTENSION = { mov: ['mov'], mp4: ['mp4'], m4v: ['m4v'] }.freeze

    APP_PREVIEW_SPEC_URL = 'https://help.apple.com/app-store-connect/#/dev4e413fcb8'.freeze

    # Validate a screenshot and inform an error message via `errors` parameter. `errors` is mutated
    # to append the messages and each message should contain the corresponding path to let users know which file is throwing the error.
    #
    # @param app_preview [AppPreview]
    # @param errors [Array<Deliver::AppPreviewValidator::ValidationError>] Pass an array object to add validation errors when detecting errors.
    #   This will be mutated to add more error objects as validation detects errors.
    # @return [Boolean] true if given app preview is valid
    def self.validate(app_preview, errors)
      # Given screenshot will be diagnosed and errors found are accumulated
      errors_found = []

      validate_file_extension_and_format(app_preview, errors_found)

      # Merge errors found into given errors array
      errors_found.each { |error| errors.push(error) }
      errors_found.empty?
    end

    def self.validate_file_extension_and_format(app_preview, errors_found)
      extension = File.extname(app_preview.path).delete('.')
      valid_file_extensions = ALLOWED_SCREENSHOT_FILE_EXTENSION.values.flatten
      is_valid_extension = valid_file_extensions.include?(extension)

      unless is_valid_extension
        errors_found << ValidationError.new(type: ValidationError::INVALID_FILE_EXTENSION,
                                            path: screenshot.path,
                                            debug_info: "Only #{valid_file_extensions.join(', ')} are allowed")
      end
    end
  end
end
