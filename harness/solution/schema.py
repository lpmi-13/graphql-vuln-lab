import strawberry
from strawberry.extensions import (
    AddValidationRules,
    DisableIntrospection,
    QueryDepthLimiter,
)
from strawberry.schema.config import StrawberryConfig

from blog.schema import Mutation, Query
from graphql_lab.validation import MaxAliasCountRule

schema = strawberry.Schema(
    query=Query,
    mutation=Mutation,
    config=StrawberryConfig(disable_field_suggestions=True),
    extensions=[
        DisableIntrospection(),
        AddValidationRules([MaxAliasCountRule]),
        QueryDepthLimiter(max_depth=5),
    ],
)
