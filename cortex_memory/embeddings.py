"""Embeddings generation using Ollama with nomic-embed-text model."""

from __future__ import annotations

import logging
from typing import Optional

import numpy as np

logger = logging.getLogger(__name__)


class EmbeddingError(Exception):
    """Raised when embedding generation fails."""


class OllamaEmbeddings:
    """Generate embeddings using Ollama's nomic-embed-text model.

    This is a local, offline embedding model optimized for code and text.
    Requires Ollama to be installed and running.
    """

    def __init__(
        self,
        model: str = "nomic-embed-text",
        host: str = "http://localhost:11434",
    ):
        """Initialize Ollama embeddings client.

        Args:
            model: Ollama model name (default: nomic-embed-text)
            host: Ollama API endpoint
        """
        self.model = model
        self.host = host
        self._client: Optional[object] = None

    def _get_client(self):
        """Lazy-load Ollama client."""
        if self._client is None:
            try:
                import ollama
                self._client = ollama.Client(host=self.host)
            except ImportError as e:
                raise EmbeddingError(
                    "ollama package not installed. Install with: pip install ollama"
                ) from e
        return self._client

    def embed_text(self, text: str) -> list[float]:
        """Generate embedding vector for a single text.

        Args:
            text: Text to embed

        Returns:
            Embedding vector (typically 768 dimensions for nomic-embed-text)

        Raises:
            EmbeddingError: If Ollama is not running or model not available
        """
        if not text or not text.strip():
            raise ValueError("Cannot embed empty text")

        try:
            client = self._get_client()
            response = client.embeddings(model=self.model, prompt=text)

            if "embedding" not in response:
                raise EmbeddingError(f"Unexpected response format: {response}")

            embedding = response["embedding"]

            # Verify dimensionality
            if not embedding or len(embedding) < 100:
                raise EmbeddingError(
                    f"Invalid embedding dimension: {len(embedding)}"
                )

            return embedding

        except Exception as e:
            if "connection" in str(e).lower():
                raise EmbeddingError(
                    "Cannot connect to Ollama. Is it running? "
                    "Start with: ollama serve"
                ) from e
            elif "not found" in str(e).lower():
                raise EmbeddingError(
                    f"Model '{self.model}' not found. "
                    f"Pull it with: ollama pull {self.model}"
                ) from e
            raise EmbeddingError(f"Embedding generation failed: {e}") from e

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Generate embeddings for multiple texts.

        Args:
            texts: List of texts to embed

        Returns:
            List of embedding vectors

        Raises:
            EmbeddingError: If any embedding fails
        """
        if not texts:
            return []

        embeddings = []
        for i, text in enumerate(texts):
            try:
                emb = self.embed_text(text)
                embeddings.append(emb)
            except Exception as e:
                logger.warning(f"Failed to embed text {i}: {e}")
                # Continue with other texts, or re-raise depending on use case
                raise EmbeddingError(
                    f"Batch embedding failed at index {i}: {e}"
                ) from e

        return embeddings

    def test_connection(self) -> bool:
        """Test if Ollama is available and model can be loaded.

        Returns:
            True if connection successful and model available
        """
        try:
            # Try to embed a simple test string
            self.embed_text("test")
            return True
        except EmbeddingError:
            return False

    def get_model_info(self) -> dict[str, object]:
        """Get information about the embedding model.

        Returns:
            Dict with model name, dimensions, and availability
        """
        try:
            # Test embedding to get dimensions
            test_emb = self.embed_text("test")
            return {
                "model": self.model,
                "host": self.host,
                "dimensions": len(test_emb),
                "available": True,
            }
        except EmbeddingError as e:
            return {
                "model": self.model,
                "host": self.host,
                "dimensions": None,
                "available": False,
                "error": str(e),
            }


def cosine_similarity(vec1: list[float], vec2: list[float]) -> float:
    """Calculate cosine similarity between two vectors.

    Args:
        vec1: First vector
        vec2: Second vector

    Returns:
        Similarity score between -1 and 1 (1 = identical)
    """
    a = np.array(vec1)
    b = np.array(vec2)

    dot = np.dot(a, b)
    norm_a = np.linalg.norm(a)
    norm_b = np.linalg.norm(b)

    if norm_a == 0 or norm_b == 0:
        return 0.0

    return float(dot / (norm_a * norm_b))
