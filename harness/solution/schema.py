import strawberry
from graphql import GraphQLError
from graphql.language import BREAK
from graphql.validation import ValidationRule
from strawberry.extensions import (
    AddValidationRules,
    DisableIntrospection,
    MaskErrors,
    QueryDepthLimiter,
)
from strawberry.schema.config import StrawberryConfig

from blog.schema import Mutation, Query

MAX_ALIASES = 15


class MaxAliasCountRule(ValidationRule):
    """Reject operations that use more than MAX_ALIASES aliased fields.

    Field aliasing lets a single request repeat the same field many times
    under different response keys. A per-request rate limiter counts one HTTP
    request regardless, so capping aliases here closes that bypass.
    """

    def __init__(self, context):
        super().__init__(context)
        self.alias_count = 0

    def enter_field(self, node, *_args):
        if node.alias is None:
            return
        self.alias_count += 1
        if self.alias_count > MAX_ALIASES:
            self.report_error(
                GraphQLError(
                    f"Too many aliases: {self.alias_count} exceeds the "
                    f"limit of {MAX_ALIASES}.",
                    node,
                )
            )
            return BREAK


schema = strawberry.Schema(
    query=Query,
    mutation=Mutation,
    config=StrawberryConfig(disable_field_suggestions=True),
    extensions=[
        DisableIntrospection(),
        # Mask only exceptions raised inside resolvers; GraphQL's own
        # validation errors carry no original_error and stay readable.
        MaskErrors(should_mask_error=lambda error: error.original_error is not None),
        AddValidationRules([MaxAliasCountRule]),
        # The deepest query the app needs (a post page) has depth 3.
        QueryDepthLimiter(max_depth=3),
    ],
)
