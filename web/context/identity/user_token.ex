defmodule Nimble.UserToken do
  @moduledoc """
  Defines a UserToken for use with authenticating and verifying User operations
  """
  use Ecto.Schema
  import Ecto.Query

  alias Nimble.{User, UserToken}

  @hash_algorithm :sha256
  @rand_size 32
  @tracking_id_size 16

  @reset_password_validity_in_days 1
  @confirm_validity_in_days 7
  @change_email_validity_in_days 7
  @session_validity_in_days 60

  schema "users_tokens" do
    field(:token, :binary)
    field(:context, :string)
    field(:sent_to, :string)
    field(:tracking_id, :string)

    belongs_to(:user, User)

    timestamps(updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    tracking_id = build_tracking_id(@tracking_id_size)

    {
      token,
      %UserToken{
        token: token,
        tracking_id: tracking_id,
        context: "session",
        user_id: user.id
      }
    }
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.
  The query returns the user found by the token.
  """
  def verify_session_token_query(token) do
    query =
      from(token in token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user
      )

    {:ok, query}
  end

  @doc """
  Builds a token with a hashed counter part.
  The non-hashed token is sent to the user e-mail while the
  hashed part is stored in the database, to avoid reconstruction.
  The token is valid for a week as long as users don't change
  their email.
  """
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    tracking_id = build_tracking_id(@tracking_id_size)

    hashed_token = :crypto.hash(@hash_algorithm, token)

    {
      Base.url_encode64(token, padding: false),
      %UserToken{
        token: hashed_token,
        tracking_id: tracking_id,
        context: context,
        sent_to: sent_to,
        user_id: user.id
      }
    }
  end

  defp build_tracking_id(size) do
    :crypto.strong_rand_bytes(size)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, size)
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.
  The query returns the user found by the token.
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from(token in token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
            select: user
          )

        {:ok, query}

      :error ->
        :error
    end
  end

  defp days_for_context("confirm"), do: @confirm_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days

  @doc """
  Checks if the token is valid and returns its underlying lookup query.
  The query returns the user token record.
  """
  def verify_change_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from(token in token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")
          )

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Returns the given token with the given context.
  """
  def token_and_context_query(token, context) do
    from(UserToken, where: [token: ^token, context: ^context])
  end

  @doc """
  Returns all session tokens except the given session token.
  """
  def user_and_session_tokens(user, token) do
    from(t in UserToken,
      where: t.token != ^token and t.user_id == ^user.id and t.context == "session"
    )
  end

  def user_and_session_tokens(user) do
    from(t in UserToken,
      where: t.user_id == ^user.id and t.context == "session"
    )
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  def user_and_contexts_query(user, :all) do
    from(t in UserToken, where: t.user_id == ^user.id, order_by: [desc: t.inserted_at])
  end

  def user_and_contexts_query(user, [_ | _] = contexts) do
    from(t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts)
  end

  def user_and_tracking_id_query(user, tracking_id) do
    from(t in UserToken, where: t.user_id == ^user.id and t.tracking_id == ^tracking_id, select: t)
  end
end
