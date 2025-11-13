
import boto3
import botocore.config
import json
from datetime import datetime

def generate_code_using_bedrock(message: str) -> str:
    prompt_text = f"""
    Human: You are a professional athelete trainer, try give a solid fittness instructions and advices on : {message}
    """

    # --- 修正后的请求体 ---
    body = {
        "inputText": prompt_text,
        "textGenerationConfig": {
            "maxTokenCount": 100,
            "temperature": 0.1,
            "topP": 0.2
            # 移除了 top_k 和 stop_sequences
        }
    }
    # -----------------------
    
    try:
        bedrock = boto3.client(
            "bedrock-runtime",
            region_name="us-east-1",
            config=botocore.config.Config(read_timeout=300, retries={"max_attempts": 3})
        )

# bedrock.invoke_model() 
        response = bedrock.invoke_model(
            body=json.dumps(body),               ##把dict。变成Jason
            modelId="amazon.titan-text-lite-v1"
        )
        print("Raw Response:", response) ## 把原始输出print出来

        """
        Raw Response: {'ResponseMetadata': {'RequestId': 
        '78b537b7-3e71-47eb-82ee-8064caec00b0', 'HTTPStatusCode': 200, 
        'HTTPHeaders': {'date': 'Tue, 11 Nov 2025 23:51:21 GMT', 
        'content-type': 'application/json', 'content-length': '475', 
        'connection': 'keep-alive', 'x-amzn-requestid': '78b537b7-3e71-47eb-82ee-8064caec00b0', 
        'x-amzn-bedrock-invocation-latency': '4031', 'x-amzn-bedrock-output-token-count': '100', 
        'x-amzn-bedrock-input-token-count': '27'}, 'RetryAttempts': 0}, 
        'contentType': 'application/json', 
        'body': <botocore.response.StreamingBody object at 0x7fd6f5d536a0>}
        """
        

        response_content = response.get("body").read().decode("utf-8")
        response_data = json.loads(response_content)
        
        # --- 修正后的响应解析 ---
        # Titan 的响应通常包含 results 字段
        code = response_data["results"][0]["outputText"].strip()
        # -----------------------

        return code

    except Exception as e:
        print("Error in generating code:", str(e))
        return ""


def save_code_to_s3(code, s3_bucket, s3_key):
    s3 = boto3.client("s3")
    try:
        s3.put_object(Bucket=s3_bucket, Key=s3_key, Body=code)
        print("Code saved to S3")
    except Exception as e:
        print("Error in saving code to S3:", str(e))


def lambda_handler(event, context):
    try:
        event_body = json.loads(event["body"])   ## event自动把api申请的dict抓过来，然后找到body。同时.loads 把jason 变成 dict。
        message = event_body.get("message", "")
      

        print("Message: 信息如下", message)
      
        
        generated_code = generate_code_using_bedrock(message)

        if generated_code:
            current_time = datetime.now().strftime("%H%M%S")
            s3_key = f"code/output/{current_time}.py"
            s3_bucket = "whatevernamesfa"

            save_code_to_s3(generated_code, s3_bucket, s3_key)
            print(generated_code)
            response_message = "Code generation complete"
        else:
            response_message = "No code was generated"

        return {
            "statusCode": 200,
            "body": json.dumps({"message": generated_code})
        }

    except Exception as e:
        print("Lambda error:", str(e))
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
