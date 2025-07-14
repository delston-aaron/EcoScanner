import requests
import os

# --- IMPORTANT ---
# 1. Place the image you want to test in the same folder as this script.
# 2. Change 'your_test_image.jpg' to the actual filename.
IMAGE_FILENAME = "full.jpg" 
DEBUG_ENDPOINT_URL = "http://127.0.0.1:8000/debug-ocr"

def run_test():
    if not os.path.exists(IMAGE_FILENAME):
        print(f"Error: The file '{IMAGE_FILENAME}' was not found in this folder.")
        print("Please place your test image here and update the filename in the script.")
        return

    with open(IMAGE_FILENAME, 'rb') as f:
        files = {'file': (IMAGE_FILENAME, f, 'image/jpeg')}
        print(f"Sending '{IMAGE_FILENAME}' to the debug endpoint...")
        
        try:
            response = requests.post(DEBUG_ENDPOINT_URL, files=files)
            
            print(f"\nResponse Status Code: {response.status_code}")
            print("--- RESPONSE FROM SERVER ---")
            print(response.text)
            print("--- END OF RESPONSE ---")

        except requests.exceptions.ConnectionError as e:
            print("\nConnection Error: Could not connect to the server.")
            print("Is your 'main.py' Uvicorn server running?")

if __name__ == "__main__":
    run_test()