from scaleway.tem.v1alpha1 import (
    TemV1Alpha1API,
    CreateEmailRequestAddress,
    DomainStatus,
)
from scaleway import Client

client = Client.from_config_file_and_env()
api = TemV1Alpha1API(client)

domain = api.list_domains_all(name="mouton.dev").pop()

if domain.status != DomainStatus.CHECKED:
    api.check_domain(domain_id=domain.id)
    api.wait_for_domain(domain_id=domain.id)

text = (
    "Hello,\n\nThis is a demo email sent from Scaleway TEM.\n\nBest regards,\nScaleway"
)

res = api.create_email(
    subject="Scaleway TEM Demo",
    text=text,
    html=text,
    to=[CreateEmailRequestAddress(email="ndemacon@scaleway.com", name=None)],
    from_=CreateEmailRequestAddress(
        email="demo@mouton.dev",
        name="Mouton Scaleway Demo",
    ),
)

for email in res.emails:
    email = api.wait_for_email(email_id=email.id)
    print(f"Email to {email.rcpt_to} sent.")
