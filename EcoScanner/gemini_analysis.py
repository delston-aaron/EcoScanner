import json
import google.generativeai as genai

# --- Configuration ---
# Replace with your actual Gemini API key
GEMINI_API_KEY = "AIzaSyCYdgi6Q3gva-FORCzGx1PGHxpg5iHScv0"
INPUT_FILENAME = "scanned_data.json"
OUTPUT_FILENAME = "analysis_result.json"

# Configure the Gemini client
genai.configure(api_key=GEMINI_API_KEY)

# This configuration is CRUCIAL for stable and consistent output
# A low temperature (0.0 to 0.2) makes the model less random.
generation_config = genai.GenerationConfig(
    temperature=0.1 
)

# Initialize the model with the stable configuration
model = genai.GenerativeModel(
    'gemini-1.5-flash',
    generation_config=generation_config
)

def analyze_ingredients_from_data(data: dict):
    ingredients = data.get("ingredients", [])
    if not ingredients:
        print("Error: No ingredients list found.")
        return

    # Step 2: Craft a detailed, rule-based prompt asking for a JSON response.
    # This is the key to getting consistent, structured data.

    prompt = f"""
    You are an expert food safety and sustainability analyst. Analyze the provided list of ingredients from a food product.

    Your response MUST be a single, valid JSON object and nothing else. Do not include any text, explanations, or markdown formatting like ```json before or after the JSON object.

     **Sustainability Grading Scale Context:**
    - **A (Excellent):** Very low environmental impact, highly sustainable, often organic/local/renewable, minimal processing.
    - **B (Good):** Low impact, common ingredients generally produced sustainably, or easily recyclable.
    - **C (Moderate):** Moderate impact, common ingredients with varying production impacts, or some processing involved.
    - **D (Poor):** High impact, problematic ingredients (e.g., unsustainable farming, high water/energy use), non-recyclable components, significant processing.
    - **E (Very Poor):** Extremely high impact, major environmental concerns (e.g., deforestation, high pollution, rare/critically endangered sources), severe processing or highly artificial.

    **JSON Structure Requirements:**
    - "ingredient_analysis": An array of objects. FOR EVERY INGREDIENT FROM THE INPUT LIST, include an object with the following keys:
        - "ingredient": (The exact name of the ingredient from the input list)
        - "eco_grade": (An eco-sustainability grade for this specific ingredient, "A", "B", "C", "D", or "E", based on the grading scale above)
        - "eco_reasoning": (A brief, factual explanation for this ingredient's eco_grade, focusing on its environmental impact or sustainable practices.)
    - "harmful_ingredients": An array of objects.For each potentially harmful ingredient, include it if:
            - it is a known health or safety risk to humans (e.g., preservatives, artificial additives, excess sugar, etc.)
            - OR it is significantly harmful to the environment, i.e., has an eco_grade of "C", "D", or "E" due to unsustainable farming, processing, or resource use.

            Even if an ingredient appears in the "ingredient_analysis" list, repeat it here if it is harmful. Do NOT skip ingredients that are only ecologically harmful. This list should combine both health-related and eco-harmful ingredients. 

        - "ingredient": (the name of the ingredient)
        - "reason": (a brief, factual explanation of why it's considered potentially harmful, e.g., 'preservative linked to health issues', 'artificial sweetener','Harmfull to the evironment and sustainability')
        - "alternative": (a specific, healthier, or more sustainable alternative ingredient)
        - "alternative_reasoning": (a brief, factual explanation of why the suggested alternative is better)
      If no harmful ingredients are found, this should be an empty array [].
    - "overall_eco_grade": (The product's overall sustainability grade, "A", "B", "C", "D", or "E", based on the combined impact of all ingredients, packaging implied)
    - "overall_eco_reasoning": (A brief string explaining the main factors that influenced the overall_eco_grade, referencing key ingredients or product characteristics.)
    - "overall_summary": (A short, one-sentence summary of the product's health and sustainability profile, considering both harmful ingredients, individual ingredient impacts, and the overall eco grade.)
    
    Here is the list of ingredients to analyze: {json.dumps(ingredients)}
    """

    print("Sending prompt to Gemini API for analysis...")
    
    # Step 3: Call the Gemini API
    try:
        response = model.generate_content(prompt)
        response_text = response.text.strip()
        analysis_data = json.loads(response_text)
        return analysis_data  # ✅ Return instead of saving to file

    except Exception as e:
        print(f"An error occurred during API call or parsing: {e}")
        print("\n--- Raw API Response for Debugging ---")
        print(response.text)
        return None

# --- Run the main function ---
if __name__ == "__main__":
    analyze_ingredients_from_data()