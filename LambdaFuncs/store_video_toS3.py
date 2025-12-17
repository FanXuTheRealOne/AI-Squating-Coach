import json
import boto3
import base64
from datetime import datetime
from APIConfig import S3_BUCKET
MAX_VIDEO_SIZE = 15 * 1024 * 1024  # 15MB

def parse_multipart(body, content_type):
    """解析 multipart/form-data"""
    if not content_type or "multipart/form-data" not in content_type:
        return None
    
    # 提取 boundary
    boundary = None
    for part in content_type.split(";"):
        part = part.strip()
        if part.startswith("boundary="):
            boundary = part.split("=", 1)[1].strip('"')
            break
    
    if not boundary:
        return None
    
    # 分割 multipart 数据
    parts = body.split(f"--{boundary}".encode())
    for part in parts:
        if b"Content-Disposition" in part:
            # 查找文件名和字段名
            header_end = part.find(b"\r\n\r\n")
            if header_end == -1:
                continue
            
            headers = part[:header_end].decode("utf-8", errors="ignore")
            data = part[header_end + 4:]
            
            # 移除末尾的 boundary 标记
            if data.endswith(b"\r\n--\r\n"):
                data = data[:-7]
            elif data.endswith(b"--\r\n"):
                data = data[:-5]
            
            # 检查是否是视频文件
            if "filename=" in headers and "video" in headers.lower():
                return data
    
    return None

def lambda_handler(event, context):
    try:
        content_type = event.get("headers", {}).get("content-type") or event.get("headers", {}).get("Content-Type", "")
        
        # 获取 body（可能是 base64 编码的）
        body = event.get("body", "")
        is_base64 = event.get("isBase64Encoded", False)
        
        if is_base64:
            body = base64.b64decode(body)
        elif isinstance(body, str):
            body = body.encode("utf-8")
        
        # 解析 multipart/form-data
        video_data = parse_multipart(body, content_type)
        
        if not video_data:
            raise ValueError("无法解析 multipart/form-data，请确保 Content-Type 为 multipart/form-data 并包含视频文件")
        
        # 检查文件大小
        if len(video_data) > MAX_VIDEO_SIZE:
            raise ValueError(f"视频文件太大: {len(video_data)} bytes，最大限制: {MAX_VIDEO_SIZE} bytes")
        
        # 生成 S3 key
        timestamp = int(datetime.now().timestamp())
        s3_key = f"squat_video/{timestamp}.mp4"
        
        # 上传到 S3
        s3 = boto3.client("s3")
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=video_data,
            ContentType="video/mp4"
        )
        
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({
                "s3Key": s3_key,
                "message": "视频上传成功"
            })
        }
            
    except Exception as e:
        print(f"Error: {str(e)}")
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

