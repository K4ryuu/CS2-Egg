---
description: >-
  This guide helps you find the credentials and values needed for setting up the
  Auto Restart feature correctly, along with tips for proper configuration.
icon: '1'
---

# Setup Auto Restart

## Steps to Setup Nest - Admin Side

1. Navigate to your <mark style="color:purple;">**Nests**</mark> page of your <mark style="color:purple;">**Admin section**</mark>.
2. Go to the nest where the egg is located at and open it.
3. Select the <mark style="color:purple;">**Variables**</mark> page.
4. For all following steps, press save after you are done. 
5. Set the default value for <mark style="color:purple;">**Auto Restart - Steam API Key**</mark> to the Steam API Key generated at https://steamcommunity.com/dev/apikey. 
6. Set the default value for <mark style="color:purple;">**Auto Restart - Check Interval**</mark> to the desired time frequency for server updates. <mark style="color:yellow;">**A longer interval is recommended to avoid rate limiting.**</mark>
7. Set the default value for <mark style="color:purple;">**Auto Restart - API URL**</mark> to your Pterodactyl panel URL. Don't include any path at the end. Example: https://panel.your-domain.com
8. Configure any <mark style="color:purple;">**Auto Restart**</mark> default setting according to your preferences, as these will apply to all new servers or servers where you change the egg to this.
9. You can also configure which settings are visible on client side.

{% hint style="danger" %}
**Avoid setting a default** <mark style="color:purple;">**Auto Restart - User API**</mark> **key value if you're hosting servers for others. This can be extracted! Each user should create their own API token.**
{% endhint %}

## Steps to Setup Server - Admin Side

1. Navigate to your <mark style="color:purple;">**Servers**</mark> page of your <mark style="color:purple;">**Admin Section**</mark>.
2. Go to the desired server you want to modify and open it.
3. Select the <mark style="color:purple;">**Startup**</mark> page.
4. Set the default value for <mark style="color:purple;">**Auto Restart - Steam API Key**</mark> to the Steam API Key generated at https://steamcommunity.com/dev/apikey.
5. Set the default value for <mark style="color:purple;">**Auto Restart - Check Interval**</mark> to the desired time frequency for server updates. A longer interval is recommended to avoid rate limiting.
6. Set the default value for <mark style="color:purple;">**Auto Restart - API URL**</mark> to your Pterodactyl panel URL. Don't include any path at the end. Example: https://panel.your-domain.com
7. Configure any <mark style="color:purple;">**Auto Restart**</mark> default setting according to your preferences.
8. Press the Save Modifications button to store your settings.

## Steps to Setup Server - Client Side

1. Access the server where you wish to activate the feature.
2. Go to the <mark style="color:purple;">**Startup**</mark> page.
3. Activate the <mark style="color:purple;">**AUTO RESTART - ENABLED**</mark> setting.
4. To add your API key, navigate to the <mark style="color:purple;">**AUTO RESTART - USER API KEY**</mark> section. You can generate this key by clicking your profile picture in the top right corner, selecting <mark style="color:purple;">**API Credentials**</mark>, or visiting [https://panel.your-domain.com/account/api](https://panel.your-domain.com/account/api). Create a new key and copy it immediately after generation, as it is only visible once. The key is typically 48 characters long.
5. Define a JSON structure containing commands and their corresponding timings to execute during the countdown to a restart to <mark style="color:purple;">**AUTO RESTART - COMMANDS**</mark>. These commands can be used to notify players about the upcoming restart or to perform any other actions. Follow the default format, where the key represents the remaining seconds before the restart, and the value specifies the command to execute.
6. Set the <mark style="color:purple;">**AUTO RESTART - COUNTDOWN INTERVAL**</mark> to the number of seconds to wait before restarting the server upon detecting a new version. It's recommended to set this value to a few minutes to allow players to be notified in advance.
7. Depending on your admin's preferences, you may have the ability to set <mark style="color:purple;">**Auto Restart - Steam API Key**</mark> to the Steam API Key generated at https://steamcommunity.com/dev/apikey. If you do not see this option in your server, this has not been made available to you. Consult with your server admin for more details.
8. Press the Save Modifications button to store your settings.
9. Restart your server, and if everything is set up correctly, you should see a green message at startup indicating that it has successfully started.

## Tips and Tricks

* If your server uses centralized and symlinked egg modifications, set the <mark style="color:purple;">**AUTO RESTART - COUNTDOWN INTERVAL**</mark> to at least 5 minutes. This allows the main server time to detect and download updates.
* If you host only your own servers, you can configure the <mark style="color:purple;">**Auto Restart**</mark> settings in the <mark style="color:purple;">**Nests**</mark> for all servers. Ensure you apply these settings before switching to this egg.
* If plugins save database changes inefficiently, consider disconnecting players briefly before a restart to trigger the plugin's save logic and ensure data is saved in time. (Rare scenarios)
* Set the <mark style="color:purple;">**Auto Restart - Check Interval**</mark> to a few minutes in order to avoid being rate limited by Steam.
