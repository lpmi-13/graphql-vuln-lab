from django.urls import path
from django.views.decorators.csrf import csrf_exempt
from django_ratelimit.decorators import ratelimit
from strawberry.django.views import GraphQLView

from blog.views import index
from graphql_lab.schema import schema

graphql_view = ratelimit(key="ip", rate="60/m", method="POST", block=True)(
    csrf_exempt(GraphQLView.as_view(schema=schema))
)

urlpatterns = [
    path("", index),
    path("graphql/", graphql_view),
]
