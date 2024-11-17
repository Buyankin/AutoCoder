#!/bin/bash

# Exit immediately if a command exits with a non-zero status and log commands
set -ex

# Get inputs from the environment
GITHUB_TOKEN="$1"
REPOSITORY="$2"
ISSUE_NUMBER="$3"
OPENAI_API_KEY="$4"

# Debugging: Print input parameters for verification
echo "GITHUB_TOKEN: $GITHUB_TOKEN"
echo "REPOSITORY: $REPOSITORY"
echo "ISSUE_NUMBER: $ISSUE_NUMBER"
echo "OPENAI_API_KEY: $OPENAI_API_KEY"

# Function to fetch issue details from GitHub API
fetch_issue_details() {
    curl -s -H "Authorization: token $GITHUB_TOKEN" \
         "https://api.github.com/repos/$REPOSITORY/issues/$ISSUE_NUMBER"
}

# Function to send a prompt to the ChatGPT model (OpenAI API)
send_prompt_to_chatgpt() {
    curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"gpt-3.5-turbo\", \"messages\": $MESSAGES_JSON, \"max_tokens\": 500}"
}

# Function to save code snippet to file
save_to_file() {
    local filename="autocoder-bot/$1"
    local code_snippet="$2"

    # Create directory and save the file
    mkdir -p "$(dirname "$filename")"
    echo -e "$code_snippet" > "$filename"
    echo "The code has been written to $filename"
}

# Fetch issue details
RESPONSE=$(fetch_issue_details)
echo "GitHub API Response: $RESPONSE" # Debug the API response

# Extract issue body
ISSUE_BODY=$(echo "$RESPONSE" | jq -r .body)

if [[ -z "$ISSUE_BODY" ]]; then
    echo 'Error: Issue body is empty or not found in the response.'
    exit 1
fi

# Define instructions for GPT
INSTRUCTIONS="Based on the description below, please generate a JSON object where the keys represent file paths and the values are the corresponding code snippets for a production-ready application. The response should be a valid strictly JSON object without any additional formatting, markdown, or characters outside the JSON structure."

# Combine instructions with issue body
FULL_PROMPT="$INSTRUCTIONS\n\n$ISSUE_BODY"

# Prepare the messages array for OpenAI API
MESSAGES_JSON=$(jq -n --arg body "$FULL_PROMPT" '[{"role": "user", "content": $body}]')
echo "Messages JSON for OpenAI: $MESSAGES_JSON" # Debug the JSON payload

# Send the prompt to ChatGPT
RESPONSE=$(send_prompt_to_chatgpt)
echo "OpenAI API Response: $RESPONSE" # Debug the API response

if [[ -z "$RESPONSE" ]]; then
    echo "Error: No response received from the OpenAI API."
    exit 1
fi

# Extract JSON dictionary from the response
FILES_JSON=$(echo "$RESPONSE" | jq -e '.choices[0].message.content | fromjson' 2>/dev/null)

if [[ -z "$FILES_JSON" ]]; then
    echo "Error: No valid JSON dictionary found in the response or the response was not valid JSON."
    exit 1
fi

# Debug: Print the parsed JSON
echo "Parsed JSON Dictionary:"
echo "$FILES_JSON" | jq .

# Iterate over the JSON dictionary and save each file
for key in $(echo "$FILES_JSON" | jq -r 'keys[]'); do
    FILENAME=$key
    CODE_SNIPPET=$(echo "$FILES_JSON" | jq -r --arg key "$key" '.[$key]')
    CODE_SNIPPET=$(echo "$CODE_SNIPPET" | sed 's/\r$//') # Normalize line endings
    save_to_file "$FILENAME" "$CODE_SNIPPET"
done

# Debug: List the created files
echo "Listing files in the autocoder-bot directory:"
ls -R autocoder-bot/

echo "All files have been processed successfully."