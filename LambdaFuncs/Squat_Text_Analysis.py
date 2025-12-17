import boto3
import json
from botocore.config import Config
from APIConfig import KNOWLEDGE_BASE_ID, MODEL_ARN

MODEL_ID = "us.amazon.nova-micro-v1:0"
REGION_NAME = "us-east-1"

def generate_fitness_advice_with_rag(message: str) -> str:
    """
    Generate professional fitness advice using RAG with Bedrock Knowledge Bases
    """
    bedrock_agent = boto3.client(
        'bedrock-agent-runtime',
        region_name=REGION_NAME,
        config=Config(
            connect_timeout=300,
            read_timeout=300,
            retries={'max_attempts': 3}
        )
    )
    
    try:
        print(f"📤 Calling Knowledge Base RAG: {KNOWLEDGE_BASE_ID}")
        print(f"📝 User question: {message}")
        
        # 使用 RAG: Retrieve and Generate
        response = bedrock_agent.retrieve_and_generate(
            input={'text': message},
            retrieveAndGenerateConfiguration={
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': KNOWLEDGE_BASE_ID,
                    'modelArn': MODEL_ARN,
                    'retrievalConfiguration': {
                        'vectorSearchConfiguration': {
                            'numberOfResults': 5,  # 检索前5个最相关的文档片段
                            'overrideSearchType': 'HYBRID'  # 混合搜索：向量+关键词
                        }
                    }
                }
            }
        )
        
        # 提取回答
        answer = response['output']['text']
        
        # 打印完整响应用于调试
        print(f"📋 RAG 完整响应: {json.dumps(response, ensure_ascii=False, indent=2)}")
        print(f"📝 RAG 生成的回答: {answer[:200]}...")  # 打印前200字符
        
        # 检查回答是否有效
        if not answer or answer.strip() == "":
            print("⚠️ RAG 返回空回答，使用 fallback")
            return generate_fitness_advice_fallback(message)
        
        # 检查是否是错误/拒绝消息
        error_phrases = [
            "unable to assist", 
            "sorry, i am unable", 
            "cannot help", 
            "not able to", 
            "i don't have",
            "i cannot",
            "i'm unable"
        ]
        answer_lower = answer.lower()
        if any(phrase in answer_lower for phrase in error_phrases):
            print(f"⚠️ RAG 返回了错误/拒绝消息，使用 fallback")
            print(f"⚠️ RAG 回答内容: {answer}")
            return generate_fitness_advice_fallback(message)
        
        # 获取来源引用（可选，用于调试）
        citations = response.get('citations', [])
        if citations:
            print(f"📚 Found {len(citations)} source citations from knowledge base")
            for i, citation in enumerate(citations, 1):
                retrieved_text = citation.get('retrievedText', '')
                print(f"   Citation {i}: {retrieved_text[:100]}...")  # 打印前100字符
        
        print(f"✅ RAG response generated successfully")
        return answer
        
    except Exception as e:
        error_msg = str(e)
        print(f"❌ RAG Error: {error_msg}")
        print(f"⚠️ Falling back to direct model call")
        # 如果RAG失败，回退到直接调用模型
        return generate_fitness_advice_fallback(message)


def generate_fitness_advice_fallback(message: str) -> str:
    """
    Fallback: Direct model call without RAG (当RAG失败时使用)
    """
    client = boto3.client(
        "bedrock-runtime",
        region_name=REGION_NAME,
        config=Config(
            connect_timeout=300,
            read_timeout=300,
            retries={'max_attempts': 3}
        )
    )
    
    # System prompt: Professional fitness coach
    system_list = [{
        "text": """You are an elite certified strength and conditioning coach with 20+ years of experience. You hold multiple certifications including CSCS (Certified Strength and Conditioning Specialist), NASM-CPT, and have a deep understanding of biomechanics, exercise physiology, and movement science.

Your expertise includes:
- Biomechanics and movement analysis
- Injury prevention and rehabilitation
- Exercise form and technique
- Program design and periodization
- Sports performance optimization
- Corrective exercise and mobility work

You provide evidence-based, detailed explanations that help users understand not just WHAT to do, but WHY. You break down complex concepts into clear, actionable advice. When answering questions, you:
1. Explain the underlying biomechanical and physiological principles
2. Provide specific, actionable guidance
3. Address common misconceptions
4. Offer practical examples and cues
5. Consider safety and injury prevention

Be thorough, professional, and educational in your responses."""
    }]
    
    # User message
    message_list = [{
        "role": "user",
        "content": [{"text": message}]
    }]
    
    # Inference configuration
    inf_params = {
        "maxTokens": 1500,
        "topP": 0.9,
        "topK": 20,
        "temperature": 0.7
    }
    
    # Request body for Nova model (messages-v1 schema)
    request_body = {
        "schemaVersion": "messages-v1",
        "messages": message_list,
        "system": system_list,
        "inferenceConfig": inf_params,
    }
    
    try:
        print(f"📤 Calling Nova model: {MODEL_ID}")
        print(f"📝 User question: {message}")
        
        response = client.invoke_model(
            modelId=MODEL_ID,
            body=json.dumps(request_body)
        )
        
        response_body = response["body"].read().decode("utf-8")
        model_response = json.loads(response_body)
        
        # Parse Nova model response
        if "output" in model_response:
            output = model_response.get("output", {})
            if "message" in output and "content" in output["message"]:
                content = output["message"]["content"]
                if content and isinstance(content, list) and len(content) > 0:
                    if isinstance(content[0], dict) and "text" in content[0]:
                        return content[0]["text"]
                    elif isinstance(content[0], str):
                        return content[0]
        
        if "text" in model_response:
            return model_response["text"]
        
        print(f"⚠️ Unexpected response format: {json.dumps(model_response, ensure_ascii=False)}")
        return "Unable to parse model response"

    except Exception as e:
        print(f"❌ Error in generating fitness advice: {str(e)}")
        return ""




def lambda_handler(event, context):
    try:
        event_body = json.loads(event.get("body", "{}"))
        message = event_body.get("message", "")
      
        if not message:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
                "body": json.dumps({"error": "Message is required"})
            }
        
        print(f"📥 Received question: {message}")
        
        # 使用 RAG 生成回答（优先使用Knowledge Base）
        advice = generate_fitness_advice_with_rag(message)
        
        if advice:
            print(f"✅ Generated advice successfully")
            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
                "body": json.dumps({"message": advice})
            }
        else:
            return {
                "statusCode": 500,
                "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
                "body": json.dumps({"error": "Failed to generate advice"})
            }

    except Exception as e:
        error_msg = str(e)
        print(f"❌ Lambda error: {error_msg}")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": error_msg})
        }
