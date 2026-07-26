from django.urls import path
from . import views

urlpatterns = [
    # POST: multipart image → skin type + disorder + routine
    path('analyze-face/', views.analyze_face, name='skin_analyze_face'),

    # GET: history of skin analyses for a user
    path('history/<int:user_id>/', views.get_skin_history, name='skin_history'),
]
