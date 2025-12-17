import json
import boto3
from datetime import datetime

S3_BUCKET = "whatevernamesfa"

def lambda_handler(event, context):
    try:
        print("📥 Lambda 函数被调用：生成预签名 URL")
        
        s3 = boto3.client("s3")
        
        # 生成唯一的 S3 key
        timestamp = int(datetime.now().timestamp())
        s3_key = f"squat_video/{timestamp}.mp4"
        
        print(f"📤 生成 S3 key: {s3_key}")
        
        # 生成预签名 URL（有效期 1 小时）
        presigned_url = s3.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': S3_BUCKET,
                'Key': s3_key,
                'ContentType': 'video/mp4'
            },
            ExpiresIn=3600
        )
        
        print(f"✅ 预签名 URL 生成成功")
        
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({
                "presignedUrl": presigned_url,
                "s3Key": s3_key
            })
        }
    except Exception as e:
        print(f"❌ Lambda 错误: {str(e)}")
        import traceback
        print(f"❌ Traceback: {traceback.format_exc()}")
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({
                "error": str(e)
            })
        }
