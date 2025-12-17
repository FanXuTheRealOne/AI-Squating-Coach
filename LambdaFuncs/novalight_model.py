import json
import boto3
from datetime import datetime
from botocore.config import Config
from APIConfig import S3_BUCKET

MODEL_ID = "us.amazon.nova-lite-v1:0"
REGION_NAME = "us-east-1"
MAX_VIDEO_SIZE = 1024 * 1024 * 1024  # 1GB (Nova 模型 S3 URI 方式的最大限制)

def get_bucket_owner() -> str:
    """获取 S3 bucket 的所有者账户 ID"""
    try:
        # 从 STS 获取当前账户 ID（Lambda 执行角色的账户）
        sts = boto3.client("sts")
        account_id = sts.get_caller_identity()["Account"]
        print(f"✅ 获取到账户 ID: {account_id}")
        return account_id
    except Exception as e:
        print(f"⚠️ 无法获取账户 ID: {str(e)}")
        # 如果无法获取，返回空字符串（某些情况下可能不需要）
        return ""

def invoke_nova_video_analysis(s3_key: str) -> str:
    client = boto3.client(
        "bedrock-runtime",
        region_name=REGION_NAME,
        config=Config(
            connect_timeout=3600,
            read_timeout=3600,
            retries={'max_attempts': 1}
        )
    )
    
    system_list = [{
        "text": """You are an elite certified strength and conditioning coach with 15+ years of experience in biomechanics and movement analysis. Your expertise includes Olympic weightlifting, powerlifting, and corrective exercise. You analyze movement patterns with precision and provide actionable, evidence-based feedback."""
    }]
    
    # 构建 S3 URI
    s3_uri = f"s3://{S3_BUCKET}/{s3_key}"
    bucket_owner = get_bucket_owner()
    
    detailed_prompt = """You are analyzing a squat video using a weighted scoring system. You MUST provide a total score out of 100 points at the very beginning of your response.

**🎯 SCORING SYSTEM (100 POINTS TOTAL):**

You must evaluate and score each category, then calculate the weighted total:

1. **Upper Body Posture – 25 points**
   - Chest Position (0-10): Chest remains lifted and open; no excessive forward collapse
   - Spine Neutrality (0-10): Back stays neutral (not rounding, not overarching)
   - Head Alignment (0-5): Head follows natural spine position without excessive tilt
   - Common Issues: Chest collapsing forward, excessive forward lean, rounding of lower back, overextension in lumbar spine

2. **Knee Alignment – 25 points** (HIGHEST PRIORITY)
   - Knees Tracking Over Toes (0-10): Knees move in the same direction as toes throughout movement
   - Inward Collapse/Knee Valgus (0-10): Degree of inward collapse; 0 points if severe
   - Outward Over-rotation (0-5): Knees pushing excessively outward
   - Positive Standard: "Knees and toes point in the same direction"

3. **Squat Depth – 20 points**
   - Depth Achieved (0-10): Thighs reach parallel or below while keeping safe form
   - Control During Descent/Ascent (0-10): Smooth, stable motion without "dropping" or bouncing
   - Note: Depth should not sacrifice spine or knee alignment

4. **Core Stability – 20 points**
   - Core Engagement (0-10): Midsection stays stable without excessive wobbling or folding
   - Pelvic Stability (0-10): No excessive anterior/posterior pelvic tilt
   - Key Observations: Torso wobble, excessive "butt wink", rib cage flare

5. **Foot Stability & Stance – 10 points**
   - Even Foot Pressure (0-5): Balanced pressure across heel, midfoot, and toes
   - Stance Consistency (0-5): Feet remain stable without lifting edges or shifting excessively

**CALCULATION FORMULA:**
Final Score = (Upper Body Score × 0.25) + (Knee Alignment Score × 0.25) + (Squat Depth Score × 0.20) + (Core Stability Score × 0.20) + (Foot Stability Score × 0.10)

**⚠️ PRIMARY FOCUS: KNEE-TO-TOE ALIGNMENT (HIGHEST PRIORITY) ⚠️**

This is the #1 most important check. You MUST carefully observe:

1. **Knee Alignment Analysis** (CRITICAL - OBSERVE FRAME BY FRAME):
   
   **HOW TO OBSERVE:**
   - Watch the video multiple times, focusing ONLY on knee and toe positions
   - Freeze-frame at key moments: start of descent, mid-descent, bottom position, start of ascent, mid-ascent
   - Draw imaginary lines: one line through the center of each knee cap, another line through the center of each foot/toes
   - Compare these lines - they should be parallel or nearly parallel
   
   **CORRECT ALIGNMENT (✅):**
   - Knees point in the SAME direction as toes throughout the ENTIRE movement
   - Knee cap center aligns with the second toe (or center of foot)
   - Both knees maintain this alignment consistently
   - No deviation inward or outward at any point
   
   **INCORRECT - KNEE VALGUS / KNEE CAVE (❌):**
   - Knees collapse INWARD toward each other (knees move toward the midline of the body)
   - Knee position is INSIDE the toe line (knees point more inward than toes)
   - This is a COMMON and DANGEROUS error - you MUST identify it if present
   - Look for: knees buckling inward, especially during descent or at bottom position
   - Even slight inward collapse should be reported
   
   **INCORRECT - KNEE VARUS / KNEE OUTWARD (❌):**
   - Knees push OUTWARD beyond toe alignment (knees point more outward than toes)
   - Knee position is OUTSIDE the toe line
   - Less common but still incorrect
   
   **REPORTING REQUIREMENTS:**
   - You MUST state clearly: "Knee alignment is CORRECT" or "Knee alignment is INCORRECT"
   - If incorrect, specify: "Knee Valgus detected" or "Knee Varus detected"
   - Identify the exact phase: "during descent", "at bottom position", "during ascent", or "throughout"
   - Note if it's: "unilateral (left/right side only)" or "bilateral (both sides)"
   - Describe severity: "slight", "moderate", or "severe"
   - If you see ANY deviation from perfect alignment, you MUST report it

2. **Upper Back Posture** (MUST CHECK):
   - Evaluate thoracic spine position throughout the movement
   - ✅ CORRECT: Neutral spine with chest up, shoulders back, upper back engaged
   - ❌ INCORRECT - Kyphosis (Rounded Upper Back): If upper back rounds forward, chest collapses, shoulders roll forward
   - ❌ INCORRECT - Excessive Extension: If over-arching the upper back
   - Check if posture breaks down at specific depth or under load
   
**IMPORTANT: If knee alignment is incorrect, this is a CRITICAL finding that must be emphasized in your report.**

**COMPREHENSIVE MOVEMENT ANALYSIS:**

3. **Squat Depth:**
   - Measure if hips descend below parallel (hip crease below top of knee)
   - Note if depth is insufficient, adequate, or excessive
   - Assess if depth is consistent across repetitions

4. **Lower Body Mechanics:**
   - Hip hinge pattern: Does the movement initiate from hips or knees?
   - Ankle mobility: Assess dorsiflexion range and heel contact
   - Foot position: Width, toe angle, and weight distribution
   - Hip drive: Power and direction of ascent from bottom position

5. **Core Stability:**
   - Lumbar spine position: Neutral, flexed, or hyperextended
   - Abdominal engagement throughout movement
   - Breathing pattern and bracing technique

6. **Bar Path & Balance:**
   - Vertical bar path vs. forward/backward drift
   - Weight distribution: Heels, midfoot, or forefoot dominant
   - Balance and stability throughout movement

7. **Tempo & Control:**
   - Descent speed: Controlled vs. uncontrolled
   - Bottom position: Pause, bounce, or immediate reversal
   - Ascent speed and power output

**OUTPUT FORMAT:**
Structure your response as a professional assessment report. 

**START YOUR ANALYSIS WITH (MANDATORY):**
1. **TOTAL SCORE (MUST BE FIRST):**
   - Begin with: "🏆 SQUAT SCORE: [XX]/100"
   - Calculate using the weighted formula above
   - Show breakdown: "Breakdown: Upper Body [XX]/25, Knee Alignment [XX]/25, Depth [XX]/20, Core [XX]/20, Foot Stability [XX]/10"
   - This MUST be the very first thing in your response, before anything else

2. Then immediately address knee-to-toe alignment with a clear statement:
   - "Knee Alignment Assessment: [CORRECT/INCORRECT]"
   - If incorrect, state the type (Valgus/Varus) and severity
   - This should be the SECOND thing you report

3. Then provide detailed analysis for each category above, including individual scores for each component

4. Use specific observations from the video, identify exact moments or phases where issues occur

5. Provide actionable corrections for any identified problems

**CRITICAL REMINDER:**
- Knee-to-toe alignment is the MOST IMPORTANT assessment
- Watch carefully - even subtle misalignment must be reported
- If knees deviate from toe direction at ANY point, you MUST identify it
- Do not miss knee valgus (inward collapse) - this is a common and serious error
- Be thorough and precise in your knee alignment analysis

Be precise, technical, and professional in your analysis."""
    
    message_list = [{
        "role": "user",
        "content": [
            {
                "video": {
                    "format": "mp4",
                    "source": {
                        "s3Location": {
                            "uri": s3_uri,
                            "bucketOwner": bucket_owner
                        }
                    }
                }
            },
            {"text": detailed_prompt}
        ]
    }]
    
    inf_params = {"maxTokens": 1500, "topP": 0.9, "topK": 20, "temperature": 0.7}
    
    request_body = {
        "schemaVersion": "messages-v1",
        "messages": message_list,
        "system": system_list,
        "inferenceConfig": inf_params,
    }
    
    request_json = json.dumps(request_body)
    request_size_mb = len(request_json) / 1024 / 1024
    print(f"📤 调用 Bedrock Nova 模型（S3 URI 方式），请求大小: {request_size_mb:.2f} MB")
    print(f"📤 S3 URI: {s3_uri}")
    
    response = client.invoke_model(modelId=MODEL_ID, body=request_json)
    response_body = response["body"].read().decode("utf-8")
    model_response = json.loads(response_body)
    
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
    
    raise ValueError(f"无法解析响应: {json.dumps(model_response, ensure_ascii=False)}")

def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
        s3_key = body.get("s3Key")
        
        if not s3_key:
            raise ValueError("请求必须包含 's3Key' 字段")
        
        print(f"📥 开始处理视频: {s3_key}")
        
        # 检查视频文件大小（通过 S3 head_object，不需要下载整个文件）
        s3 = boto3.client("s3")
        try:
            head_response = s3.head_object(Bucket=S3_BUCKET, Key=s3_key)
            video_size = head_response.get("ContentLength", 0)
            video_size_mb = video_size / 1024 / 1024
            print(f"✅ 视频文件大小: {video_size_mb:.2f} MB")
            
            if video_size > MAX_VIDEO_SIZE:
                raise ValueError(f"视频文件太大: {video_size_mb:.2f} MB，最大限制: {MAX_VIDEO_SIZE / 1024 / 1024:.0f} MB")
        except Exception as e:
            print(f"⚠️ 无法获取视频文件信息: {str(e)}，继续处理...")
        
        # 使用 S3 URI 方式，不需要下载和 Base64 编码
        print(f"✅ 使用 S3 URI 方式，无需下载视频")
        
        analysis_result = invoke_nova_video_analysis(s3_key)
        print("✅ Bedrock 分析完成")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        result_key = s3_key.replace("squat_video/", "squat_video_model_output/").replace(".mp4", f"_{timestamp}.json")
        
        s3 = boto3.client("s3")
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=result_key,
            Body=json.dumps({"video_s3_key": s3_key, "analysis": analysis_result, "timestamp": timestamp}, ensure_ascii=False).encode("utf-8"),
            ContentType="application/json"
        )
        
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"Squat_analysis": analysis_result, "result_s3_key": result_key})
        }
            
    except Exception as e:
        error_msg = str(e)
        print(f"❌ Lambda 错误: {error_msg}")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": error_msg})
        }
