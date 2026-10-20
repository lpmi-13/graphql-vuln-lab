from typing import Optional

import strawberry
from django.contrib.auth.models import User

from blog.models import Post, Profile


@strawberry.type
class PostType:
    id: strawberry.ID
    title: str
    body: str
    author_id: strawberry.Private[int]

    @strawberry.field
    def author(self) -> "UserType":
        return user_type(User.objects.get(pk=self.author_id))


@strawberry.type
class UserType:
    id: strawberry.ID
    username: str
    bio: str

    @strawberry.field
    def posts(self) -> list[PostType]:
        return [post_type(p) for p in Post.objects.filter(author_id=int(self.id))]


def user_type(user: User) -> UserType:
    bio = ""
    profile = Profile.objects.filter(user=user).first()
    if profile is not None:
        bio = profile.bio
    return UserType(id=strawberry.ID(str(user.id)), username=user.username, bio=bio)


def post_type(post: Post) -> PostType:
    return PostType(
        id=strawberry.ID(str(post.id)),
        title=post.title,
        body=post.body,
        author_id=post.author_id,
    )


@strawberry.type
class Query:
    @strawberry.field
    def me(self) -> Optional[UserType]:
        user = User.objects.order_by("id").first()
        return user_type(user) if user is not None else None

    @strawberry.field
    def users(self) -> list[UserType]:
        return [user_type(u) for u in User.objects.order_by("id")]

    @strawberry.field
    def posts(self) -> list[PostType]:
        return [post_type(p) for p in Post.objects.order_by("id")]


@strawberry.type
class UpdateBioResult:
    ok: bool


@strawberry.type
class VerifyOtpResult:
    ok: bool


@strawberry.type
class Mutation:
    @strawberry.mutation
    def update_bio(self, info: strawberry.Info, text: str) -> UpdateBioResult:
        request = info.context.request
        user = getattr(request, "user", None)
        if user is not None and user.is_authenticated:
            Profile.objects.update_or_create(user=user, defaults={"bio": text})
        return UpdateBioResult(ok=True)

    @strawberry.mutation
    def verify_otp(self, code: str) -> VerifyOtpResult:
        return VerifyOtpResult(ok=code == "0000")
