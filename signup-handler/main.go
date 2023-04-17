package myfunc

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"

	"github.com/go-playground/validator/v10"
	tem "github.com/scaleway/scaleway-sdk-go/api/tem/v1alpha1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

var (
	api *tem.API

	senderEmail string
	senderName  string
)

func init() {
	senderEmail = os.Getenv("SENDER_EMAIL")
	senderName = os.Getenv("SENDER_NAME")

	if senderEmail == "" {
		panic("SENDER_EMAIL environment variable is not set")
	}

	if senderName == "" {
		panic("SENDER_NAME environment variable is not set")
	}

	components := strings.Split(senderEmail, "@")
	domainName := components[1]

	profile := scw.LoadEnvProfile()
	if profile == nil {
		panic("no profile found")
	}

	client, err := scw.NewClient(scw.WithProfile(profile))
	if err != nil {
		panic(err)
	}

	api = tem.NewAPI(client)
	domains, err := api.ListDomains(&tem.ListDomainsRequest{
		Name:   &domainName,
		Region: scw.RegionFrPar,
	}, scw.WithAllPages())
	if err != nil {
		panic(err)
	}

	domain := domains.Domains[0]
	if domain.Status != tem.DomainStatusChecked {
		_, err := api.CheckDomain(&tem.CheckDomainRequest{
			DomainID: domain.ID,
			Region:   scw.RegionFrPar,
		})
		if err != nil {
			panic(err)
		}

		_, err = api.WaitForDomain(&tem.WaitForDomainRequest{
			DomainID: domain.ID,
			Region:   scw.RegionFrPar,
		})
		if err != nil {
			panic(err)
		}
	}
}

type Body struct {
	Username string `json:"username" validate:"required"`
	Email    string `json:"email" validate:"email,required"`
}

func Handle(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	var body Body
	err := json.NewDecoder(r.Body).Decode(&body)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	err = validator.New().Struct(body)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(err.Error()))
		return
	}

	text := "Hello " + body.Username + ",\n\n"
	text += "Welcome to my cool product!\n\n"
	text += "Best regards,\n"
	text += "The Amazing Super Product,\n"

	_, err = api.CreateEmail(&tem.CreateEmailRequest{
		Region: scw.RegionFrPar,
		From: &tem.CreateEmailRequestAddress{
			Name:  &senderName,
			Email: senderEmail,
		},
		To: []*tem.CreateEmailRequestAddress{
			{
				Email: body.Email,
			},
		},
		Subject: "Welcome to my cool product!",
		Text:    text,
		HTML:    text,
	})
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(err.Error()))
		return
	}

	w.WriteHeader(http.StatusOK)
}
