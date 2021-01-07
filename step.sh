#!/bin/bash
set -ex

# Client
CLIENT_ID="${client_id}"
CLIENT_SECRET="${client_secret}"

# App
APP_ID="${app_id}"
APP_NAME="${app_name}"
APK_FILE_NAME="${apk_name}"
APK_PATH="${apk_path}"

AUTH_URL="https://api.amazon.com/auth/O2/token"
API_URL="https://developer.amazon.com/api/appstore/v1"

get_header() {
  sed -n "s/^$1: //p" <<< "$2"
}

# request LWA(Login With Amazon) Access Token
token_response=$(curl --silent -X POST $AUTH_URL \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=appstore::apps:readwrite")

# check for request error
if [ "$(jq 'has("error_description")' <<< "$token_response")" = "true" ]; then
  jq -r '.error_description' <<< "$token_response"
  exit 1
fi

access_token=$(jq -r '.access_token' <<< "$token_response")

# get Edit
response=$(curl --silent -X GET "${API_URL}/applications/${APP_ID}/edits" -H "Authorization: Bearer ${access_token}")
edit_id=$(jq -r '.id' <<< "$response")

if [ "$edit_id" = "null" ]; then
  # create Edit if it doesn't exist
  echo "Creating new Edit"
  response=$(curl --silent -X POST "${API_URL}/applications/${APP_ID}/edits" -H "Authorization: Bearer ${access_token}")
  edit_id=$(jq -r '.id' <<< "$response")
else
  echo "Using existing Edit"
fi

# submit APK
response=$(curl --silent -X GET "${API_URL}/applications/${APP_ID}/edits/${edit_id}/apks" -H "Authorization: Bearer ${access_token}")
apk_id=$(jq -r --arg name "$APP_NAME" '.[] | select(.name == $name) | .id' <<< "$response")

if [ "$apk_id" != "null" ]; then
  echo "Replacing existing $APP_NAME APK"

  response=$(curl -i --silent -X GET "${API_URL}/applications/${APP_ID}/edits/${edit_id}/apks/${apk_id}" -H "Authorization: Bearer ${access_token}")
  etag=$(get_header "ETag" "$response")

  curl --fail -X PUT "${API_URL}/applications/${APP_ID}/edits/${edit_id}/apks/${apk_id}/replace" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/octet-stream" \
    -H "If-Match: ${etag}" \
    -H "fileName: ${APK_FILE_NAME}" \
    --data-binary "@${APK_PATH}"
else
  echo "Adding new APK"

  curl --fail -X POST "${API_URL}/applications/${APP_ID}/edits/${edit_id}/apks/upload" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/octet-stream" \
    -H "fileName: ${APK_FILE_NAME}" \
    --data-binary "@${APK_PATH}"
fi

exit $?
