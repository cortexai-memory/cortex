"""Tests for embeddings module."""

from unittest.mock import MagicMock, patch

import pytest

from cortex_memory.embeddings import EmbeddingError, OllamaEmbeddings, cosine_similarity


class TestOllamaEmbeddings:
    """Test OllamaEmbeddings class."""

    def test_init_defaults(self):
        """Test default initialization."""
        embeddings = OllamaEmbeddings()
        assert embeddings.model == "nomic-embed-text"
        assert embeddings.host == "http://localhost:11434"
        assert embeddings._client is None

    def test_init_custom(self):
        """Test initialization with custom params."""
        embeddings = OllamaEmbeddings(
            model="custom-model",
            host="http://custom:8080",
        )
        assert embeddings.model == "custom-model"
        assert embeddings.host == "http://custom:8080"

    def test_embed_text_empty(self):
        """Test error on empty text."""
        embeddings = OllamaEmbeddings()

        with pytest.raises(ValueError, match="Cannot embed empty text"):
            embeddings.embed_text("")

        with pytest.raises(ValueError, match="Cannot embed empty text"):
            embeddings.embed_text("   ")

    def test_embed_batch_empty(self):
        """Test batch with empty input."""
        embeddings = OllamaEmbeddings()
        result = embeddings.embed_batch([])

        assert result == []


class TestCosineSimilarity:
    """Test cosine similarity function."""

    def test_identical_vectors(self):
        """Test similarity of identical vectors."""
        vec = [1.0, 2.0, 3.0]
        similarity = cosine_similarity(vec, vec)
        assert similarity == pytest.approx(1.0, abs=1e-6)

    def test_orthogonal_vectors(self):
        """Test similarity of orthogonal vectors."""
        vec1 = [1.0, 0.0, 0.0]
        vec2 = [0.0, 1.0, 0.0]
        similarity = cosine_similarity(vec1, vec2)
        assert similarity == pytest.approx(0.0, abs=1e-6)

    def test_opposite_vectors(self):
        """Test similarity of opposite vectors."""
        vec1 = [1.0, 2.0, 3.0]
        vec2 = [-1.0, -2.0, -3.0]
        similarity = cosine_similarity(vec1, vec2)
        assert similarity == pytest.approx(-1.0, abs=1e-6)

    def test_similar_vectors(self):
        """Test similarity of similar vectors."""
        vec1 = [1.0, 2.0, 3.0]
        vec2 = [1.1, 2.1, 2.9]
        similarity = cosine_similarity(vec1, vec2)
        assert 0.9 < similarity < 1.0

    def test_zero_vector(self):
        """Test handling of zero vectors."""
        vec1 = [0.0, 0.0, 0.0]
        vec2 = [1.0, 2.0, 3.0]
        similarity = cosine_similarity(vec1, vec2)
        assert similarity == 0.0

    def test_different_scale(self):
        """Test vectors with different magnitudes but same direction."""
        vec1 = [1.0, 2.0, 3.0]
        vec2 = [2.0, 4.0, 6.0]
        similarity = cosine_similarity(vec1, vec2)
        assert similarity == pytest.approx(1.0, abs=1e-6)
