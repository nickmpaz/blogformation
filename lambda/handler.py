import json
import time
import pathlib
import os
import logging
from tempfile import TemporaryDirectory
from subprocess import run, check_output, CalledProcessError
import boto3

logging.basicConfig(format='%(levelname)s: %(message)s', level=logging.DEBUG)

PROD = os.environ.get('PROD')
API_ENDPOINT = "https://api.blogformation.net"

BLOG = 'blog'
PROGRESS = 'progress'
ERROR = 'error'
CLONE_ERROR = "Could not clone this repository. It is either not public, or doesn't exist."
PROCESSING_ERROR = "There was an error while processing this repository."
OK = {
    'statusCode': 200,
    'headers': {'Content-Type': 'application/json'},
    'body': ''
}


def send_to_connection(message, data, event):
    if PROD:
        payload = json.dumps(
            {'message': message, 'data': data}).encode('utf-8')
        gatewayapi = boto3.client(
            "apigatewaymanagementapi", endpoint_url=API_ENDPOINT)
        connection = event["requestContext"].get("connectionId")
        gatewayapi.post_to_connection(ConnectionId=connection, Data=payload)
    else:
        logging.info(
            "Sending to connection\n\tMessage: %s\n\tData: %s" % (message, data))


def handler(event, context):
    if PROD:
        repo = json.loads(event.get("body")).get('data')
    else:
        repo = 'https://github.com/nickmpaz/freereads.git'

    with TemporaryDirectory() as tmpdir:
        try:
            logging.info("Cloning " + repo)
            clone_process = run(['git', 'clone', repo, tmpdir],
                                capture_output=True, check=True)
        except CalledProcessError as e:
            logging.warning("Error cloning " + repo)
            send_to_connection(ERROR, CLONE_ERROR, event)
            return OK
        try:
            logging.info("Processing commits")
            commits_process = run(['git', '-C', tmpdir, "rev-list",
                                   "master", "--reverse"], capture_output=True, check=True)
            commits_raw = commits_process.stdout.decode('utf-8')
            commits = commits_raw.split('\n')[:-1]
        except CalledProcessError as e:
            logging.warning("Error processing commits")
            send_to_connection(ERROR, PROCESSING_ERROR, event)
            return OK

        steps = []

        for i in range(1, len(commits)):

            current_commit = commits[i]
            previous_commit = commits[i-1]

            try:
                logging.info("Getting commit message for commit %s" %
                             current_commit)
                commit_message_process = run(
                    ['git', '-C', tmpdir, 'show', '-s', '--format=%B', current_commit], capture_output=True, check=True)
                commit_message = commit_message_process.stdout.decode(
                    'utf-8').strip()
            except CalledProcessError as e:
                logging.warning(
                    "Error getting commit message for commit %s" % current_commit)
                send_to_connection(ERROR, PROCESSING_ERROR, event)
                return OK

            try:
                logging.info("Diffing commit %s" % current_commit)
                commit_diff_process = run(
                    ['git', '-C', tmpdir, 'diff', previous_commit, current_commit], capture_output=True, check=True)
                commit_diff = commit_diff_process.stdout.decode('utf-8')
            except CalledProcessError as e:
                logging.warning("Error diffing commit %s" % current_commit)
                send_to_connection(ERROR, PROCESSING_ERROR, event)
                return OK

            steps.append([commit_message, commit_diff])
            send_to_connection(PROGRESS, int((i / len(commits)) * 100), event)

    try:
        logging.info('Building blog')
        blog_str = ''
        for i, step in enumerate(steps):
            blog_str += 'Step %d: %s\n\n' % (i + 1, step[0])
            current_step_diff = step[1]
            blog_str += '\n'.join(['\t' +
                                   line for line in current_step_diff.split('\n')]) + '\n'

        send_to_connection(BLOG, blog_str, event)
    except Exception as e:
        logging.warning('Error building blog')
        send_to_connection(ERROR, PROCESSING_ERROR, event)
        return OK

    logging.info('Done, returning')
    return OK
