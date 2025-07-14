# EcoScanner - Sustainability Scanner App

A Flutter application built for a hackathon that analyzes food packaging labels to provide sustainability scores and flag potentially harmful ingredients.

## 🚀 About The Project

This app allows users to take a picture of a food product's ingredients list. The image is processed by an OCR service, and the extracted text is then sent to the Gemini API for a detailed analysis. The frontend, built with Flutter, presents this analysis in a beautiful and easy-to-understand format.

## ✨ Features

- **Image-to-Text:** Uses an OCR API to extract ingredients from an image.
- **AI-Powered Analysis:** Leverages the Gemini API to analyze ingredients for sustainability and health impacts.
- **Eco-Grading System:** Assigns an overall sustainability grade (A-E) to the product.
- **Red Flag System:** Highlights potentially harmful or unsustainable ingredients.
- **Modern UI:** A clean, animated, and responsive user interface built with Flutter.

## 🛠️ Built With

- **Frontend:** [Flutter](https://flutter.dev/)
- **Backend:** [Python (FastAPI)](https://fastapi.tiangolo.com/)
- **APIs:**
    - [Google Gemini](https://ai.google.dev/)
    - [OCR.space](https://ocr.space/)

## screenshots
- Put some screenshots here. You can drag and drop them directly into the editor on GitHub.

## 🏁 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [Python 3.8+](https://www.python.org/downloads/)
- A Gemini API Key

### How to Run

1.  **Clone the repo**
    ```sh
    git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
    ```
2.  **Setup the Backend**
    ```sh
    cd backend_folder # Navigate to your Python backend folder
    pip install -r requirements.txt
    uvicorn main:app --reload
    ```
3.  **Setup the Frontend**
    - Create a `lib/config.dart` file.
    - Add your Gemini API Key:
      ```dart
      class ApiKeys {
        static const String gemini = "YOUR_API_KEY_HERE";
      }
      ```
    - Run the app:
      ```sh
      cd frontend_folder # Navigate to your Flutter project folder
      flutter pub get
      flutter run -d chrome
      ```
