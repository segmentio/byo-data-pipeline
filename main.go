package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/firehose"
)

func main() {
	client := New("calvinfo")
	for i := 0; i < 100; i++ {
		err := client.Send(map[string]interface{}{
			"user_id": "calvin",
			"event":   "ate a bagel",
			"company": "Segment",
		})
		if err != nil {
			fmt.Printf("an error occurred sending to firehose: %v\n", err)
		} else {
			fmt.Println("sent successfully.")
		}
		<-time.After(200 * time.Millisecond)
	}
}

type Client struct {
	firehose *firehose.Firehose
	name     *string
}

func New(stream string) *Client {
	sess, err := session.NewSession()
	if err != nil {
		fmt.Println("failed to create session,", err)
		panic(err)
	}

	svc := firehose.New(sess)

	return &Client{
		firehose: svc,
		name:     &stream,
	}
}

func (c *Client) Send(v interface{}) error {
	body, err := json.Marshal(v)
	if err != nil {
		return err
	}

	_, err = c.firehose.PutRecord(&firehose.PutRecordInput{
		DeliveryStreamName: c.name,
		Record:             &firehose.Record{Data: body},
	})

	return err
}
