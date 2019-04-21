# Define Variables
$sonarr_episodefile_id = $env:sonarr_episodefile_id
$sonarr_series_id = $env:sonarr_series_id
$sonarr_series_title = $env:sonarr_series_title
$sonarr_episodefile_seasonnumber = $env:sonarr_episodefile_seasonnumber
$sonarr_episodefile_episodenumbers = $env:sonarr_episodefile_episodenumbers

$apikey="" # Your Sonarr API key 
$sonarr_address="http://localhost:8989" # Your Sonarr address (including base_url) 
$pushkey="" # Your PushBullet API key
$pushtag="" # Add the tag for your Pushbullet Channel or leave blank for direct push notifications

# Change $null to "username" / "password" if you use basic authentication in Radarr
$user = $null
$pass = $null

if (($null -ne $user) -and ($null -ne $pass)){
# Create authentication value
$pair = "$($user):$($pass)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"

# Grab series information
$sonarr_series=$(Invoke-WebRequest  -URI $sonarr_address/api/episode?seriesId=$sonarr_series_id -UseBasicParsing -Header @{"X-Api-Key" = $apikey; "Authorization" = $basicAuthValue }) | ConvertFrom-Json
Invoke-WebRequest $Sonarr_image -UseBasicParsing -OutFile "$PSScriptRoot\tvposter.jpg" -Header @{"Authorization" = $basicAuthValue }
} Else {
# Grab series information
$sonarr_series=$(Invoke-WebRequest  -URI $sonarr_address/api/episode?seriesId=$sonarr_series_id -UseBasicParsing -Header @{"X-Api-Key" = $apikey}) | ConvertFrom-Json
Invoke-WebRequest $Sonarr_image -UseBasicParsing -OutFile "$PSScriptRoot\tvposter.jpg"
}

# Grab episode details
$sonarr_episode_title = $sonarr_series | Where-Object {$_.episodeFileId -eq $sonarr_episodefile_id} | Select-Object -ExpandProperty title
$sonarr_episode_description = $sonarr_series | Where-Object {$_.episodeFileId -eq $sonarr_episodefile_id} | Select-Object -ExpandProperty overview

# Upload Poster
$pushbody = @{
    "file_name" = "poster.jpg"
    "file_type" = "image/jpeg"
}

$uploadImage = Invoke-WebRequest -Method POST -Uri "https://api.pushbullet.com/v2/upload-request" -UseBasicParsing -Header @{"Access-Token" = $pushkey} -Body $pushbody | convertfrom-json
$uploadData = $uploadImage.data[0]

$FilePath = "$PSScriptRoot\poster.jpg";
$fileBytes = [System.IO.File]::ReadAllBytes($FilePath);
$fileEnc = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($fileBytes);
$boundary = [System.Guid]::NewGuid().ToString(); 
$LF = "`r`n";

$bodyLines = ( 
    "--$boundary",
    "Content-Disposition: form-data; name=`"awsaccesskeyid`"$LF", 
    $uploadData.awsaccesskeyid,
    "--$boundary",
    "Content-Disposition: form-data; name=`"acl`"$LF", 
    $uploadData.acl,
    "--$boundary",
    "Content-Disposition: form-data; name=`"key`"$LF", 
    $uploadData.key,
    "--$boundary",
    "Content-Disposition: form-data; name=`"signature`"$LF", 
    $uploadData.signature,
    "--$boundary",
    "Content-Disposition: form-data; name=`"policy`"$LF", 
    $uploadData.policy,
    "--$boundary",
    "Content-Disposition: form-data; name=`"content-type`"$LF", 
    "image/jpeg",
    "--$boundary",
    "Content-Disposition: form-data; name=`"file`"$LF", 
    $fileEnc,
    "--$boundary--$LF" 
) -join $LF

Invoke-RestMethod -Uri $uploadImage.upload_url -Method Post -UseBasicParsing -ContentType "multipart/form-data; boundary=`"$boundary`"" -Body $bodyLines | convertfrom-json

rm "$PSScriptRoot\poster.jpg"

# Format content
$pushtitle = $sonarr_series_title + " - S" + $sonarr_episodefile_seasonnumber + ":E" + $sonarr_episodefile_episodenumbers
$pushmessage = $sonarr_episode_title + " - " + $sonarr_episode_description

# Prepare push notification body

$pushbody = @{
    title = $pushtitle
    type = 'file'
    file_name = $uploadImage.file_name
    body = $pushmessage
    file_type = $uploadImage.file_type
    file_url = $uploadImage.file_url
    channel_tag = $pushtag
}

# Send push notification
Invoke-WebRequest -Method POST -Uri "https://api.pushbullet.com/v2/pushes" -UseBasicParsing -Header @{"Access-Token" = $pushkey} -Body $pushBody