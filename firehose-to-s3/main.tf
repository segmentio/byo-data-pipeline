variable "name" {}

variable "buffer_size" {
  default = 5
}

variable "buffer_interval" {
  default = 5
}

/**
 * Our S3 bucket will be the sink for the firehose
 * delivery stream.
 */

resource "aws_s3_bucket" "bucket" {
  bucket = "${var.name}-firehose-sink"
  acl    = "private"

  tags {
    Name = "${var.name}"
  }
}

/**
 * The firehose delivery stream should give us an output
 * that we can use to actually send data.
 */

resource "aws_iam_role" "firehose_role" {
  name = "${var.name}_firehose_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "firehose_policy" {
  name = "firehose-stream-policy"
  role = "${aws_iam_role.firehose_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
       "Effect": "Allow",
       "Action":
       [
           "s3:AbortMultipartUpload",
           "s3:GetBucketLocation",
           "s3:GetObject",
           "s3:ListBucket",
           "s3:ListBucketMultipartUploads",
           "s3:PutObject"
       ],
       "Resource":
       [
           "${aws_s3_bucket.bucket.arn}",
           "${aws_s3_bucket.bucket.arn}/*"
       ]
     }
  ]
}
EOF
}

resource "aws_kinesis_firehose_delivery_stream" "stream" {
  name        = "${var.name}"
  destination = "s3"

  s3_configuration {
    role_arn        = "${aws_iam_role.firehose_role.arn}"
    bucket_arn      = "${aws_s3_bucket.bucket.arn}"
  }
}

/**
 * Outputs.
 */

output "name" { value = "${var.name}" }
