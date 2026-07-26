from django.urls import path
from . import views
from purepick_core import views as core_views
from purepick_core.task_views import get_task_status
from purepick_core.password_reset_views import request_password_reset, confirm_password_reset
from purepick_core.notification_views import register_fcm_token
from .pdf_views import export_scan_pdf

urlpatterns = [
    # ── Auth ──────────────────────────────────────────────────────────────────
    path('register/',       core_views.register_user),
    path('login/',          core_views.login_user),
    path('google-login/',   core_views.google_login),
    path('token/refresh/',  core_views.refresh_token),
    path('logout/',         core_views.logout_user),
    path('delete-account/', core_views.delete_account),

    # ── Password reset (no JWT required — user is logged out) ─────────────────
    path('password-reset/request/', request_password_reset),
    path('password-reset/confirm/', confirm_password_reset),

    # ── Task polling ──────────────────────────────────────────────────────────
    path('task/<str:task_id>/', get_task_status),

    # ── Profile ───────────────────────────────────────────────────────────────
    path('profile/update/',         core_views.update_profile),
    path('profile/<int:user_id>/',  core_views.get_profile),

    # ── AI Analysis (async) ───────────────────────────────────────────────────
    path('analyze/',         views.analyze_ingredients),
    path('scan-label/',      views.scan_label_image),
    path('barcode-lookup/',  views.lookup_barcode),       # NEW: Batch 4
    path('alternatives/',    views.get_alternatives),

    # ── History ───────────────────────────────────────────────────────────────
    path('history/<int:user_id>/', core_views.get_history),

    # ── Saved Products ────────────────────────────────────────────────────────
    path('saved/add/',                      core_views.save_product),
    path('saved/<int:user_id>/',            core_views.get_saved),
    path('saved/delete/<int:product_id>/',  core_views.delete_saved),

    # ── AI Chat & Tips (async) ────────────────────────────────────────────────
    path('chat/',                       views.chat_with_ai),
    path('ai-tips/<int:user_id>/',      views.get_ai_tips),

    # ── Home stats ────────────────────────────────────────────────────────────
    path('home-stats/<int:user_id>/', views.get_home_stats),

    # ── [NEW] SkinCast Weather Logic ──────────────────────────────────────────
    path('skincast/',   views.get_skincast),
    path('dashboard/',  views.get_dashboard),
    path('log-skin/',   views.save_skin_log),

    # ── Notifications (FCM) ───────────────────────────────────────────────────
    path('notifications/register-token/', register_fcm_token),

    # ── PDF Export ─────────────────────────────────────────────────────────────
    path('scan/<int:scan_id>/export-pdf/', export_scan_pdf),

    # ── Health check (used by Dockerfile HEALTHCHECK + load balancers) ────────
    path('health/', views.health_check),
]
