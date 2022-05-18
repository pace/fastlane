require_relative '../model'
module Spaceship
  class ConnectAPI
    class AppClipDefaultExperience
      include Spaceship::ConnectAPI::Model

      attr_accessor :action
      attr_accessor :app_clip_default_experience_localizations

      attr_mapping(
        'action' => 'action',
        'appClipDefaultExperienceLocalizations' => 'app_clip_default_experience_localizations'
      )

      def self.type
        'appClipDefaultExperiences'
      end

      #
      # API
      #

      def self.create(client: nil, app_clip_id:, app_store_version_id:, attributes:, template_default_experience_id: nil)
        client ||= Spaceship::ConnectAPI
        return client.post_app_clip_default_experience(app_clip_id: app_clip.id, app_store_version_id: version.id, attributes: { action: action }, template_default_experience_id: template_default_experience_id)
      end

      def self.get(client: nil, app_clip_default_experience_id:, filter: {}, includes: {}, limit: nil, sort: nil)
        client ||= Spaceship::ConnectAPI
        resps = client.get_app_clip_default_experience(app_clip_default_experience_id: app_clip_default_experience_id, filter: filter, includes: includes, limit: limit, sort: sort).all_pages
        return resps.flat_map(&:to_models).first
      end

      def update(client: nil, attributes:)
        client ||= Spaceship::ConnectAPI
        return client.patch_app_clip_default_experience(default_experience_id: id, attributes: { action: action })
      end
    end
  end
end
