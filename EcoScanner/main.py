# ======================================================================
# 1. IMPORT EVERYTHING YOU NEED AT THE TOP
# ======================================================================
import io
import re # Make sure to add this import at the top of main.py
import requests
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import JSONResponse
from PIL import Image
from pyzbar.pyzbar import decode as decode_barcode

# === ADD THIS SECTION FOR CORS ===
from fastapi.middleware.cors import CORSMiddleware

# ======================================================================
# 2. CREATE THE FASTAPI APP INSTANCE
# ======================================================================
app = FastAPI()

# === CONFIGURE CORS MIDDLEWARE HERE ===
# This tells your backend to allow requests from any origin.
# It's essential for letting your browser-based frontend talk to your backend.
origins = ["*"]  # Allow all origins

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],  # Allow all methods (GET, POST, etc.)
    allow_headers=["*"],  # Allow all headers
)
# === END OF CORS SECTION ===


# ======================================================================
# 3. DEFINE YOUR HELPER FUNCTIONS
# ======================================================================

# ======================================================================
# 3. DEFINE YOUR HELPER FUNCTIONS (REVISED)
# ======================================================================

def get_text_from_image_ocr_space(image_bytes, api_key='K85653573188957'):
    """
    Sends an image to the OCR.space API and returns the cleaned ingredients list.
    This new version is smarter and more robust.
    """
    payload = {'apikey': api_key, 'language': 'eng', 'detectOrientation': True}
    files = {'file': ('image.jpg', image_bytes, 'image/jpeg')}
    
    try:
        response = requests.post('https://api.ocr.space/parse/image', data=payload, files=files)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"API request failed: {e}")
        return []

    result = response.json()
    if not result.get('ParsedResults') or not result['ParsedResults'][0].get('ParsedText'):
        print(f"OCR.space Error: {result.get('ErrorMessage', 'No text found')}")
        return []

    raw_text = result['ParsedResults'][0]['ParsedText']
    
    # --- START OF NEW, SMARTER LOGIC ---
    
    # Replace all newline characters with spaces for easier processing
    text_blob = raw_text.replace('\n', ' ').replace('\r', ' ')

    # Use regex to find the text block starting with "Ingredients" (or similar)
    # and stopping before "Nutrition Facts" (or similar).
    # The (.*?) is a non-greedy match, which is key to stopping at the first end-word.
    match = re.search(
        r'(ingredients|contains|ingredients:)\s*[:]?\s*(.*?)(?:nutrition|allergy|manufactured|warning|$)',
        text_blob,
        re.IGNORECASE | re.DOTALL
    )

    if not match:
        print("Could not find a clear ingredients block in the text.")
        return []

    # We only want the second captured group, which is the ingredients list itself
    ingredients_block = match.group(2)

    # Clean the block: remove text in parentheses, replace semicolons with commas
    cleaned_block = re.sub(r'\(.*?\)', '', ingredients_block) # Remove anything in parentheses
    cleaned_block = cleaned_block.replace(';', ',')

    # Split by comma and clean up each ingredient
    ingredients = [
        ing.strip() for ing in cleaned_block.split(',') if ing.strip() and len(ing.strip()) > 1
    ]
    # --- END OF NEW, SMARTER LOGIC ---

    print(f"Successfully extracted {len(ingredients)} ingredients.")
    return ingredients

def get_ingredients_from_barcode(barcode_value):
    api_url = f"https://world.openfoodfacts.org/api/v0/product/{barcode_value}.json"
    response = requests.get(api_url)
    if response.status_code == 200:
        data = response.json()
        if data.get("status") == 1 and "product" in data:
            product = data["product"]
            return {
                "productName": product.get("product_name_en", "N/A"),
                "ingredients": product.get("ingredients_text_en", "Not found").split(',')
            }
    return None


# ======================================================================
# 4. DEFINE YOUR API ENDPOINT
# ======================================================================

@app.post("/scan")
async def scan_image(scanType: str = Form(...), file: UploadFile = File(...)):
    contents = await file.read()

    if scanType == "barcode":
        image = Image.open(io.BytesIO(contents))
        barcodes = decode_barcode(image)
        if not barcodes:
            raise HTTPException(status_code=400, detail="No barcode found in image.")
        
        barcode_value = barcodes[0].data.decode("utf-8")
        product_info = get_ingredients_from_barcode(barcode_value)

        if not product_info:
            raise HTTPException(status_code=404, detail="Product not found in database.")

        return JSONResponse(content={
            "source": "barcode_lookup",
            "barcode": barcode_value,
            **product_info
        })

    elif scanType == "ocr":
        ingredients_list = get_text_from_image_ocr_space(contents, api_key='K85653573188957')

        if not ingredients_list:
             raise HTTPException(status_code=500, detail="Could not extract ingredients from image. The image might be blurry or contain no text.")

        return JSONResponse(content={
            "source": "image_ocr_space",
            "ingredients": ingredients_list
        })

    else:
        raise HTTPException(status_code=400, detail="Invalid scanType. Must be 'barcode' or 'ocr'.")
    
# ======================================================================
# 5. ADD THIS TEMPORARY DEBUG ENDPOINT
# ======================================================================

@app.post("/debug-ocr")
async def debug_ocr_image(file: UploadFile = File(...)):
    """
    This endpoint is ONLY for debugging. It takes an image, sends it to the 
    OCR service, and prints the FULL raw JSON response to the terminal. 
    It helps us see exactly what the OCR service sees.
    """
    print("\n--- INITIATING OCR DEBUG ---")
    
    image_bytes = await file.read()
    
    payload = {'apikey': 'K85653573188957', 'language': 'eng', 'detectOrientation': True}
    files = {'file': ('debug_image.jpg', image_bytes, 'image/jpeg')}
    
    try:
        response = requests.post('https://api.ocr.space/parse/image', data=payload, files=files)
        response.raise_for_status()
        
        # We print the raw JSON response here
        result = response.json()
        print("--- OCR.SPACE RAW RESPONSE ---")
        import json
        print(json.dumps(result, indent=2)) # Pretty-print the JSON
        print("--- END OF RAW RESPONSE ---\n")
        
        # Also return it so we can see it in our test script
        return result
        
    except requests.exceptions.RequestException as e:
        print(f"API request failed: {e}")
        raise HTTPException(status_code=500, detail=f"API request failed: {e}")