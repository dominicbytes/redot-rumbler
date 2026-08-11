# Redot Rumbler addon

Install this directory as `res://addons/redot-rumbler/`, then enable **Redot Rumbler** in Project Settings > Plugins.

Create one `RumbleLiveClient` per connected Rumble API credential. Configure only non-secret publisher/application/session identifiers in code. Supply the private Live Stream API URL through runtime UI or `connect_api_url()`; never store it in a scene, resource, project setting, argument, environment variable, fixture, screenshot, or log.

The addon is read-only because Rumble does not document outbound chat, moderation, programmable rewards, raids, or media URL routes in Live Stream API v1.1.
