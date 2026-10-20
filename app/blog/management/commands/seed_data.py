from django.contrib.auth.models import User
from django.core.management.base import BaseCommand

from blog.models import Post, Profile

USERS = [
    ("amara", "Platform engineer. Coffee, cats, and container logs.", [
        ("Scaling our ingest pipeline", "Notes on the move to async workers."),
        ("Postmortem: the Friday outage", "What we learned from the cache stampede."),
    ]),
    ("devon", "Backend developer working on payments.", [
        ("Idempotency keys in practice", "How we stopped double-charging customers."),
    ]),
    ("priya", "Security researcher and occasional blogger.", [
        ("A gentle intro to threat modeling", "Start with the data, not the diagram."),
        ("Why I still read RFCs", "The specs are better than the tutorials."),
    ]),
]


class Command(BaseCommand):
    help = "Seed the database with demo users, profiles, and posts."

    def handle(self, *args, **options):
        if User.objects.exists():
            self.stdout.write("Data already present; skipping seed.")
            return

        for username, bio, posts in USERS:
            user = User.objects.create_user(
                username=username, password="changeme123"
            )
            Profile.objects.create(user=user, bio=bio)
            for title, body in posts:
                Post.objects.create(author=user, title=title, body=body)

        self.stdout.write(self.style.SUCCESS("Seeded demo data."))
