import argparse

import boto3
from botocore.exceptions import ClientError


def list_s3_objects(bucket_name, prefix='', region_name=None):
    session_kwargs = {}
    if region_name:
        session_kwargs['region_name'] = region_name

    session = boto3.Session(**session_kwargs)
    s3 = session.client('s3')
    paginator = s3.get_paginator('list_objects_v2')
    page_iterator = paginator.paginate(Bucket=bucket_name, Prefix=prefix)

    objects = []
    for page in page_iterator:
        for obj in page.get('Contents', []):
            objects.append(obj)

    return objects


def main():
    parser = argparse.ArgumentParser(description='List all objects in an S3 bucket.')
    parser.add_argument('bucket', help='Name of the S3 bucket')
    parser.add_argument('--prefix', default='', help='Filter objects by prefix')
    parser.add_argument('--region', default=None, help='AWS region name')
    args = parser.parse_args()

    try:
        objects = list_s3_objects(args.bucket, args.prefix, args.region)
        for obj in objects:
            print(obj['Key'])
        print(f'Total objects: {len(objects)}')
    except ClientError as e:
        print(f'Error listing objects: {e}')


if __name__ == '__main__':
    main()
