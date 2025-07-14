# ======================================================================
# 1. IMPORTS
# ======================================================================
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional

# ======================================================================
# 2. DATA MODEL (Pydantic)
# ======================================================================
# This defines the structure of the JSON we expect to receive from the first backend.
# FastAPI uses this for automatic validation. If the incoming data doesn't match
# this structure, it will automatically return an error.

class IngredientPayload(BaseModel):
    source: str
    ingredients: List[str]
    # These fields are optional because they only exist for barcode scans
    productName: Optional[str] = None
    barcode: Optional[str] = None

# ======================================================================
# 3. APP INITIALIZATION
# ======================================================================
app = FastAPI()

# ======================================================================
# 4. API ENDPOINT
# ======================================================================
# This endpoint listens for POST requests at the path "/process-ingredients".
# This path must match the AI_BACKEND_URL variable in your main.py file.

@app.post("/process-ingredients")
async def process_ingredients(payload: IngredientPayload):
    """
    Receives ingredient data, prints it to the console, and simulates
    processing by an AI model.
    """
    
    # --- 1. Display the received data in the terminal ---
    # This confirms that the data pipeline is working correctly.
    print("\n" + "="*40)
    print("--- AI BACKEND: DATA RECEIVED SUCCESSFULLY ---")
    print("="*40)
    print(f"Source of Data: {payload.source}")
    
    if payload.productName:
        print(f"Product Name: {payload.productName}")
    
    print(f"Ingredients List ({len(payload.ingredients)} items):")
    for i, ingredient in enumerate(payload.ingredients, 1):
        print(f"  {i}. {ingredient.strip()}")
    print("="*40 + "\n")

    # --- 2. Simulate AI Model Processing ---
    # In a real application, this is where you would feed the
    # `payload.ingredients` list into your machine learning model.
    # For example: `analysis = my_model.predict(payload.ingredients)`
    
    # --- 3. Return a confirmation response ---
    # This response is sent back to your first server (main.py).
    return {
        "status": "success",
        "message": f"Data for '{payload.productName or 'scanned image'}' received and processed."
    }

# To run this file, save it and run this in a NEW, SEPARATE terminal:
# uvicorn ai_model_backend:app --reload --port 8001