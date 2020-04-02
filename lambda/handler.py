import json
import time
import pathlib
import os
from tempfile import TemporaryDirectory
from subprocess import run, check_output, CalledProcessError
import boto3

CLONE_ERROR = "Could not clone this repository. It is either not public, or doesn't exist."

class ChangedFile():

    def __init__(self, name: str, diff: str):
        self.name = name
        self.diff = diff

    def __str__(self):
        return self.name

class Step():

    def __init__(self, message: str, changes: list):
        self.message = message
        self.changes = changes

    def __str__(self):
        return self.message

def _send_to_connection(data, event):
    gatewayapi = boto3.client("apigatewaymanagementapi",
                              endpoint_url="https://api.blogformation.net")
    return gatewayapi.post_to_connection(ConnectionId=event["requestContext"].get("connectionId"),
                                         Data=json.dumps(data).encode('utf-8'))

def _send_error(error, event):
    _send_to_connection({
        'message': 'error',
        'data': error
    }, event)

def my_handler(event, context):

    test = event.get('test')

    repo = json.loads(event.get("body")).get('data')

    with TemporaryDirectory() as tmpdir:
        try:
            clone_process = run(['git', 'clone', repo, tmpdir], capture_output=True, check=True)
        except CalledProcessError as e:
            _send_error(CLONE_ERROR, event)
            raise e
        try:
            commits_process = run(['git', '-C', tmpdir, "rev-list", "master", "--reverse"], capture_output=True, check=True)
        except CalledProcessError as e: 
            raise e
        commits_raw = commits_process.stdout.decode('utf-8')
        commits = commits_raw.split('\n')[:-1]
        steps = []

        for i in range(1, len(commits)):

            current_commit = commits[i]
            previous_commit = commits[i-1]
            try:
                commit_message_process = run(['git', '-C', tmpdir, 'show', '-s', '--format=%B', current_commit], capture_output=True, check=True)
            except CalledProcessError as e: 
                raise e
            commit_message = commit_message_process.stdout.decode('utf-8').strip()
            try:
                changed_files_process = run(['git', '-C', tmpdir, 'diff-tree', '-r', '--no-commit-id', '--name-only', current_commit], capture_output=True, check=True)
            except CalledProcessError as e: 
                raise e
            changed_files_raw = changed_files_process.stdout.decode('utf-8')
            changed_files = changed_files_raw.split('\n')[:-1]
            changes = []
            for f in changed_files:
                try:
                    file_diff_process = run(['git', '-C', tmpdir,'diff', '--color-words', previous_commit, current_commit, f], capture_output=True, check=True)
                except CalledProcessError as e: 
                    raise e
                file_diff = file_diff_process.stdout.decode('utf-8')
                changes.append(ChangedFile(f, file_diff))
            steps.append(Step(commit_message, changes))

            if not test:
                _send_to_connection({
                    'message': 'progress',
                    'data': int((i / len(commits)) * 100)
                }, event)

    blog_str = ''

    for step in steps:
        blog_str += 'MESSAGE: ' + step.message + '\n\n'
        for change in step.changes:
            blog_str += '\tCHANGE: ' + change.name + '\n\n'
            blog_str += '\n'.join(['\t\t' + line for line in change.diff.split('\n')]) + '\n'
        blog_str += '=========================================================\n\n'

    if not test:
        _send_to_connection({
            'message': 'blog',
            'data': blog_str
        }, event)

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': ''
    }
