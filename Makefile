

seed:
	go run main.go

firehose-to-s3:
	terraform get ./firehose-to-s3
	terraform apply ./firehose-to-s3

destroy-firehose-to-s3:
	terraform destroy ./firehose-to-s3

firehose-to-redshift:
	terraform get ./firehose-to-redshift
	terraform apply ./firehose-to-redshift

destroy-firehose-to-redshift:
	terraform destroy ./firehose-to-redshift

clean-bucket:
	aws rm s3://${BUCKET}/*

.PHONY: firehose-to-s3
