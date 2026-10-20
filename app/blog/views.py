from django.http import HttpResponse, JsonResponse
from django.views.decorators.csrf import ensure_csrf_cookie


def index(request):
    return HttpResponse(
        "Acme Social API. The GraphQL endpoint is at /graphql/.\n",
        content_type="text/plain",
    )


@ensure_csrf_cookie
def csrf_cookie(request):
    return JsonResponse({"detail": "CSRF cookie set"})
