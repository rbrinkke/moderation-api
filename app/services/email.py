import httpx
from app.config import settings
import structlog

logger = structlog.get_logger()

class EmailAPIClient:
    """Client for email-api service"""

    def __init__(self, base_url: str):
        self.base_url = base_url
        self.client = httpx.AsyncClient(timeout=30.0)

    async def send_email(self, to: str, template: str, context: dict):
        """
        Send email via email-api service.

        Args:
            to: Recipient email address
            template: Email template name
            context: Template context data
        """
        try:
            response = await self.client.post(
                f"{self.base_url}/emails/send",
                json={
                    "to": to,
                    "template": template,
                    "context": context
                }
            )
            response.raise_for_status()
            logger.info("email_sent", to=to, template=template)
            return response.json()
        except httpx.HTTPError as e:
            # Log error but don't fail the request
            logger.error("email_send_failed", error=str(e), to=to, template=template)
            # Email failure should not break the API response
            return None

    async def close(self):
        """Close HTTP client"""
        await self.client.aclose()

# Global email client instance
email_client = EmailAPIClient(settings.EMAIL_API_URL)
