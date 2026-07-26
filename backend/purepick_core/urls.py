from django.urls import path, include

urlpatterns = [
    path('api/', include('scanner.urls')),
    # ← Skin Facial Analysis routes (merged from standalone AI skin app)
    path('api/skin/', include('skin_analysis.urls')),
]
