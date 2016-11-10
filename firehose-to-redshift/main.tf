variable "name" {
}

variable "buffer_size" {
  default = 5
}

variable "buffer_interval" {
  default = 5
}

variable "database_name" {
  default = "firehose"
}

variable "data_table_name" {
  default = "events"
}

variable "region" {
  default = "us-west-2"
}

/**
 * To avoid putting the username and password in the source repo,
 * these can be input or populated separately via terraform.tfvars
 */

variable "username" {
}

variable "password" {
}

# http://docs.aws.amazon.com/firehose/latest/dev/controlling-access.html#using-iam-rs-vpc
variable "firehose_ips" {
  default {
    "us-west-2" = "52.89.255.224/27"
  }
}

variable "quicksight_ips" {
  default = "52.23.63.224/27"
}

/**
 * Boot a VPC for redshift to live within. It's possible that
 * we could add this to an existing VPC as well, but this
 * simplifies the demo by using a few different subnets.
 */

module "vpc" {
  source = "github.com/segmentio/stack//vpc"

  cidr               = "10.30.0.0/16"
  internal_subnets   = ["10.30.0.0/19"]
  external_subnets   = ["10.30.32.0/20"]
  availability_zones = ["us-west-2a"]
  environment        = "prod"
  name               = "firehose"
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
 * We can use a redshift instance to analyze the datasets.
 */

resource "aws_redshift_subnet_group" "redshift" {
  name       = "redshift-firehose"
  subnet_ids = ["${module.vpc.external_subnets}"]
}

resource "aws_security_group" "redshift" {
  name        = "allow_firehose"
  description = "allow firehose traffic"
  vpc_id      = "${module.vpc.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${lookup(var.firehose_ips, var.region)}", "${var.quicksight_ips}"]
  }
}

resource "aws_redshift_cluster" "redshift" {
  cluster_identifier        = "${var.name}"
  database_name             = "${var.database_name}"
  node_type                 = "dc1.large"
  cluster_type              = "single-node"
  master_username           = "${var.username}"
  master_password           = "${var.password}"
  vpc_security_group_ids    = ["${aws_security_group.redshift.id}"]
  cluster_subnet_group_name = "${aws_redshift_subnet_group.redshift.id}"
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
     },
     {
        "Effect": "Allow",
        "Action": [
            "logs:PutLogEvents"
        ],
        "Resource": [
            "${aws_cloudwatch_log_stream.to_s3.arn}",
            "${aws_cloudwatch_log_stream.to_redshift.arn}"
        ]
     }
  ]
}
EOF
}

/**
 * The cloudwatch log groups are responsible for logging the errors
 * within our pipeline.
 **/

resource "aws_cloudwatch_log_group" "firehose" {
  name = "firehose"
}

resource "aws_cloudwatch_log_stream" "to_s3" {
  name           = "${var.data_table_name}-to-s3"
  log_group_name = "${aws_cloudwatch_log_group.firehose.name}"
}

resource "aws_cloudwatch_log_stream" "to_redshift" {
  name           = "${var.data_table_name}-to-redshift"
  log_group_name = "${aws_cloudwatch_log_group.firehose.name}"
}

/**
 * The firehose stream itself is where we can deliver messages to redshift.
 **/

resource "aws_kinesis_firehose_delivery_stream" "stream" {
  name        = "${var.name}"
  destination = "redshift"

  s3_configuration {
    role_arn   = "${aws_iam_role.firehose_role.arn}"
    bucket_arn = "${aws_s3_bucket.bucket.arn}"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "${aws_cloudwatch_log_group.firehose.name}"
      log_stream_name = "${aws_cloudwatch_log_stream.to_s3.name}"
    }
  }

  redshift_configuration {
    role_arn        = "${aws_iam_role.firehose_role.arn}"
    cluster_jdbcurl = "jdbc:redshift://${aws_redshift_cluster.redshift.endpoint}/${aws_redshift_cluster.redshift.database_name}"
    copy_options    = "FORMAT JSON as 'auto'"
    data_table_name = "${var.data_table_name}"
    username        = "${var.username}"
    password        = "${var.password}"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "${aws_cloudwatch_log_group.firehose.name}"
      log_stream_name = "${aws_cloudwatch_log_stream.to_redshift.name}"
    }
  }
}

/**
 * Outputs.
 */

output "name" {
  value = "${var.name}"
}

output "endpoint" {
  value = "${aws_redshift_cluster.redshift.endpoint}"
}