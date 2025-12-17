# AI Squatting Coach

From Gym to Your Pocket — Your pro-level 24/7 AI fitness coach.

## Overview

An iOS application that uses AI-powered video analysis to provide real-time feedback on squat form. The app leverages AWS Bedrock's multimodal AI models to analyze workout videos and deliver professional coaching advice.

## Architecture

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   iOS Client    │ ───▶ │   AWS Lambda    │ ───▶ │  AWS Bedrock    │
│   (SwiftUI)     │      │   (Python)      │      │  (Nova Models)  │
└─────────────────┘      └─────────────────┘      └─────────────────┘
        │                        │
        │                        ▼
        │                ┌─────────────────┐
        └──────────────▶ │   Amazon S3     │
                         │ (Video Storage) │
                         └─────────────────┘
```

## AI Components

### Video Analysis (Nova Lite)
- Accepts video uploads up to 1GB via S3 URI
- Analyzes squat form using a 100-point scoring system
- Evaluates: knee alignment, upper body posture, squat depth, core stability, and foot positioning
- Provides detailed feedback with specific improvement suggestions

### Text Q&A (Nova Micro + RAG)
- Retrieval-Augmented Generation using a fitness knowledge base
- Answers user questions about squat techniques and workout advice
- Combines vector similarity search with keyword matching for accurate retrieval

## Project Structure

```
├── FrontEnd/           # iOS application (SwiftUI)
│   ├── ContentView     # Main UI and chat interface
│   ├── CameraService   # Video recording
│   └── Services        # API communication
│
└── LambdaFuncs/        # AWS Lambda functions (Python)
    ├── Video Analysis  # Nova Lite model invocation
    ├── Text Analysis   # RAG-based Q&A with Nova Micro
    └── S3 Upload       # Presigned URL generation
```

## Tech Stack

- **Frontend**: SwiftUI, AVFoundation
- **Backend**: AWS Lambda, API Gateway
- **AI**: AWS Bedrock (Nova Lite, Nova Micro)
- **Storage**: Amazon S3
- **Knowledge Base**: Amazon Bedrock Knowledge Bases with hybrid search
