import pytest
import asyncio
from httpx import AsyncClient
from app.main import app
from app.services.database import db

@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for async tests"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

@pytest.fixture
async def client():
    """Create test client"""
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac

@pytest.fixture
async def admin_token():
    """Generate admin JWT token for testing"""
    # TODO: Generate valid JWT with admin role
    # This requires JWT_SECRET_KEY from settings
    return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test-admin-token"

@pytest.fixture
async def user_token():
    """Generate user JWT token for testing"""
    # TODO: Generate valid JWT with regular user role
    return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test-user-token"
