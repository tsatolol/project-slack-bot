import json
import os
import re
import uuid

import boto3
from botocore.config import Config
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler


sqs = boto3.client("sqs")
sqs_queue_url = os.environ.get("SQS_QUEUE_NAME")

app = App(
    token=os.environ.get("SLACK_BOT_TOKEN"),
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    process_before_response=True,
)

@app.event("app_mention")
def handle_app_mention_events(event, say):
    result = say(text=f"Please wait a moment...")
    channel_id = event["channel"]
    input_text = re.sub("<@.+>", "", event["text"]).strip()

    sqs.send_message(
        QueueUrl=sqs_queue_url,
        MessageBody=json.dumps({
            "channel_id": channel_id,
            "input_text": input_text,
        })
    )

def lambda_handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
