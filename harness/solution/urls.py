from django.urls import path
from django_ratelimit.decorators import ratelimit
from strawberry.django.views import GraphQLView

from blog.views import csrf_cookie, index
from graphql_lab.schema import schema

graphql_view = ratelimit(key="ip", rate="60/m", method="POST", block=True)(
    GraphQLView.as_view(schema=schema)
)

urlpatterns = [
    path("", index),
    path("api/csrf/", csrf_cookie),
    path("graphql/", graphql_view),
]
