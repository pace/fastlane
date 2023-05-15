require_relative 'module'
require 'spaceship/connect_api/models/app_preview_set'

module Deliver
  # AppPreview represents one app preview for one specific locale and
  # device type.
  class AppPreview
    #
    module ScreenSize
      # iPhone 4
      IOS_35 = "iOS-3.5-in"
      # iPhone 5
      IOS_40 = "iOS-4-in"
      # iPhone 6, 7, & 8
      IOS_47 = "iOS-4.7-in"
      # iPhone 6s Plus, 7 Plus, & 8 Plus
      IOS_55 = "iOS-5.5-in"
      # iPhone Xs
      IOS_58 = "iOS-5.8-in"
      # iPhone 14 Pro
      IOS_61 = "iOS-6.1-in"
      # iPhone Xs Max
      IOS_65 = "iOS-6.5-in"
      # iPhone 14 Pro Max
      IOS_67 = "iOS-6.7-in"

      # iPad
      IOS_IPAD = "iOS-iPad"
      # iPad 10.5
      IOS_IPAD_10_5 = "iOS-iPad-10.5"
      # iPad 11
      IOS_IPAD_11 = "iOS-iPad-11"
      # iPad Pro
      IOS_IPAD_PRO = "iOS-iPad-Pro"
      # iPad Pro (12.9-inch) (3rd generation)
      IOS_IPAD_PRO_12_9 = "iOS-iPad-Pro-12.9"

      # Apple TV
      APPLE_TV = "Apple-TV"

      # Mac
      MAC = "Mac"
    end

    # @return [Deliver::ScreenSize] the screen size (device type)
    #  specified at {Deliver::ScreenSize}
    attr_accessor :screen_size

    attr_accessor :path

    attr_accessor :language

    # @param path (String) path to the screenshot file
    # @param language (String) Language of this screenshot (e.g. English)
    def initialize(path, language)
      self.path = path
      self.language = language
      self.screen_size = self.class.determine_preview_size(path)
    end

    # The iTC API requires a different notation for the device
    def device_type
      matching = {
        ScreenSize::IOS_35 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_35,
        ScreenSize::IOS_40 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_40,
        ScreenSize::IOS_47 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_47, # also 7 & 8
        ScreenSize::IOS_55 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_55, # also 7 Plus & 8 Plus
        ScreenSize::IOS_58 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_58,
        ScreenSize::IOS_61 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_61,
        ScreenSize::IOS_65 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_65,
        ScreenSize::IOS_67 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPHONE_67,
        ScreenSize::IOS_IPAD => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_97,
        ScreenSize::IOS_IPAD_10_5 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_105,
        ScreenSize::IOS_IPAD_11 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_PRO_3GEN_11,
        ScreenSize::IOS_IPAD_PRO => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_PRO_129,
        ScreenSize::IOS_IPAD_PRO_12_9 => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::IPAD_PRO_3GEN_129,
        ScreenSize::MAC => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::DESKTOP,
        ScreenSize::APPLE_TV => Spaceship::ConnectAPI::AppPreviewSet::PreviewType::APPLE_TV
      }
      return matching[self.screen_size]
    end

    # Nice name
    def formatted_name
      matching = {
        ScreenSize::IOS_35 => "iPhone 4",
        ScreenSize::IOS_40 => "iPhone 5",
        ScreenSize::IOS_47 => "iPhone 6", # also 7 & 8
        ScreenSize::IOS_55 => "iPhone 6s Plus", # also 7 Plus & 8 Plus
        ScreenSize::IOS_58 => "iPhone Xs",
        ScreenSize::IOS_61 => "iPhone 14 Pro",
        ScreenSize::IOS_65 => "iPhone Xs Max",
        ScreenSize::IOS_67 => "iPhone 14 Pro Max",
        ScreenSize::IOS_IPAD => "iPad",
        ScreenSize::IOS_IPAD_10_5 => "iPad 10.5",
        ScreenSize::IOS_IPAD_11 => "iPad 11",
        ScreenSize::IOS_IPAD_PRO => "iPad Pro",
        ScreenSize::IOS_IPAD_PRO_12_9 => "iPad Pro (12.9-inch) (3rd generation)",
        ScreenSize::MAC => "Mac",
        ScreenSize::APPLE_TV => "Apple TV"
      }
      return matching[self.screen_size]
    end

    # reference: https://help.apple.com/app-store-connect/#/devd274dd925
    def self.devices
      # This list does not include iPad Pro 12.9-inch (3rd generation)
      # because it has same resoluation as IOS_IPAD_PRO and will clobber
      return {
        ScreenSize::IOS_67 => "ios67",
        ScreenSize::IOS_65 => "ios65",
        ScreenSize::IOS_61 => "ios61",
        ScreenSize::IOS_58 => "ios58",
        ScreenSize::IOS_55 => "ios55",
        ScreenSize::IOS_47 => "ios47",
        ScreenSize::IOS_40 => "ios40",
        ScreenSize::IOS_35 => "ios35",
        ScreenSize::IOS_IPAD_PRO => "iosipadpro",
        ScreenSize::IOS_IPAD_11 => "iosipad11",
        ScreenSize::IOS_IPAD_10_5 => "iosipad10_5",
        ScreenSize::IOS_IPAD => "iosipad",
        ScreenSize::APPLE_TV => "appletv",
        ScreenSize::MAC => "mac"
      }
    end

    def self.determine_preview_size(path)
      filename = Pathname.new(path).basename.to_s
      devices.each do |screen_size, name|
        if filename.downcase.include?(name.downcase)
          return screen_size
        end
      end
      nil
    end
  end

  ScreenSize = AppPreview::ScreenSize
end
