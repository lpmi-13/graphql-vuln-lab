from django.http import HttpResponse


def index(request):
    return HttpResponse(
        "<!doctype html>\n"
        "<title>Acme Social API</title>\n"
        '<p>Acme Social API. The GraphQL endpoint is at <a href="graphql/">/graphql/</a>.</p>\n'
    )
