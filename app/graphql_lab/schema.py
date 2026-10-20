import strawberry

from blog.schema import Mutation, Query

schema = strawberry.Schema(query=Query, mutation=Mutation)
