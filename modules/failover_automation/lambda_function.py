import json
import os
import time

import boto3
from botocore.exceptions import ClientError


PRIMARY_HEALTH_ALARM_NAME = os.environ["PRIMARY_HEALTH_ALARM_NAME"]
SECONDARY_REGION = os.environ["SECONDARY_REGION"]
SECONDARY_ASG_NAME = os.environ["SECONDARY_ASG_NAME"]
SECONDARY_RDS_IDENTIFIER = os.environ["SECONDARY_RDS_IDENTIFIER"]
DESIRED_CAPACITY = int(os.environ.get("DESIRED_CAPACITY", "2"))


def _log(message):
    print(message)


def _parse_sns_message(event):
    record = event["Records"][0]
    sns_message = record["Sns"]["Message"]
    return json.loads(sns_message)


def _is_primary_alarm(payload):
    return payload.get("AlarmName") == PRIMARY_HEALTH_ALARM_NAME and payload.get("NewStateValue") == "ALARM"


def _promote_rds():
    rds = boto3.client("rds", region_name=SECONDARY_REGION)
    try:
        _log(f"Promoting RDS read replica {SECONDARY_RDS_IDENTIFIER} in {SECONDARY_REGION}")
        rds.promote_read_replica(DBInstanceIdentifier=SECONDARY_RDS_IDENTIFIER)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code not in {"InvalidDBInstanceState", "DBInstanceAlreadyExists", "DBInstanceNotFound"}:
            raise
        _log(f"RDS promotion skipped/ignored: {code}")

    waiter = rds.get_waiter("db_instance_available")
    waiter.wait(DBInstanceIdentifier=SECONDARY_RDS_IDENTIFIER, WaiterConfig={"Delay": 30, "MaxAttempts": 20})


def _scale_secondary_asg():
    autoscaling = boto3.client("autoscaling", region_name=SECONDARY_REGION)
    _log(f"Setting desired capacity for {SECONDARY_ASG_NAME} to {DESIRED_CAPACITY}")
    autoscaling.set_desired_capacity(
        AutoScalingGroupName=SECONDARY_ASG_NAME,
        DesiredCapacity=DESIRED_CAPACITY,
        HonorCooldown=False,
    )


def lambda_handler(event, context):
    payload = _parse_sns_message(event)
    _log(f"Received alarm payload: {json.dumps(payload)}")

    if not _is_primary_alarm(payload):
        _log("Message ignored: not the primary Route 53 alarm in ALARM state.")
        return {"status": "ignored"}

    _promote_rds()
    _scale_secondary_asg()

    return {
        "status": "failover_triggered",
        "alarm": PRIMARY_HEALTH_ALARM_NAME,
        "secondary_region": SECONDARY_REGION,
        "secondary_asg": SECONDARY_ASG_NAME,
        "secondary_rds": SECONDARY_RDS_IDENTIFIER,
    }
