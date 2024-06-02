import base64
import json
import os
import sys
import uuid

import boto3
from botocore.config import Config
from slack_sdk import WebClient


webclient = WebClient(token=os.environ.get("SLACK_BOT_TOKEN"))

# Bedrock runtime
bedrock_runtime = boto3.client('bedrock-runtime')

# S3 bucket
my_config = Config(region_name="us-east-1", signature_version="s3v4")
s3 = boto3.client("s3", config=my_config)
bucket_name = os.environ.get("S3_BUCKET_NAME")


def generate_answer(input_text):
    response = bedrock_runtime.invoke_model(
        modelId='stability.stable-diffusion-xl-v1',
        accept='image/png',
        contentType='application/json',
        body='{"text_prompts": [{"text":"'+input_text+'"}]}',
    )

    random_uuid = uuid.uuid4().hex 
    s3_key = random_uuid + '.png'
    s3.upload_fileobj(
        response['body'], 
        bucket_name, 
        s3_key, 
        ExtraArgs={'ContentType': 'image/png'}
    )
    presigned_url = s3.generate_presigned_url(
        'get_object',
        Params={'Bucket': bucket_name,'Key': s3_key},
        ExpiresIn=3600
    )
    
    return presigned_url


def lambda_handler(event, context):
    body = json.loads(event["Records"][0]["body"])
    channel_id = body.get("channel_id")
    input_text = body.get("input_text")

    output_text = generate_answer(input_text)

    result = webclient.chat_postMessage(
        channel=channel_id,
        text=output_text,
    )
