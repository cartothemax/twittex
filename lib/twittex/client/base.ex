defmodule Twittex.Client.Base do
  @moduledoc """
  A behaviour module for implementing your own Twitter client.

  It implements the `GenServer` behaviour, and keeps the authentication state
  during the entire process livetime.

  ## Example

  To create a client, create a new module and `use Twittex.Client.Base` as follow:

      defmodule TwitterBot do
        use Twittex.Client.Base

        def search(term, options \\ []) do
          get "/search/tweets.json?" <> URI.encode_query(Dict.merge(%{q: term}, options))
        end
      end

  This client works as a singleton and can be added to a supervisor tree:

      worker(TwitterBot, [])

  And this is how you may use it:

      iex> TwitterBot.search "#myelixirstatus", count: 3
      {:ok, %{}}
  """

  alias Twittex.API
  alias Twittex.Client.Stream

  use GenServer

  @doc """
  Starts the process linked to the current process.

  ## Options

  * `:username` - Twitter username or email address
  * `:password` - Twitter password

  Other options are passed to `GenServer._start_link/1`.
  """
  @spec start_link(Keyword.t) :: GenServer.on_start
  def start_link(options \\ []) do
    {username, options} = Keyword.pop(options, :username, Application.get_env(:twittex, :username))
    {password, options} = Keyword.pop(options, :password, Application.get_env(:twittex, :password))

    if username && password do
      GenServer.start_link(__MODULE__, {username, password}, options)
    else
      GenServer.start_link(__MODULE__, nil, options)
    end
  end

  @doc """
  Issues a GET request to the given url.

  Returns `{:ok, response}` if the request is successful, `{:error, reason}`
  otherwise.

  See `Twittex.API.request/5` for more detailed information.
  """
  @spec get(pid, String.t, API.headers, Keyword.t) :: {:ok, %{}} | {:error, HTTPoison.Error.t}
  def get(pid, url, headers \\ [], options \\ []) do
    GenServer.call(pid, {:get, url, "", headers, options})
  end

  @doc """
  Same as `get/4` but raises `HTTPoison.Error` if an error occurs during the
  request.
  """
  @spec get!(pid, String.t, API.headers, Keyword.t) :: %{}
  def get!(pid, url, headers \\ [], options \\ []) do
    case get(pid, url, headers, options) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Issues a POST request to the given url.

  Returns `{:ok, response}` if the request is successful, `{:error, reason}`
  otherwise.

  See `Twittex.API.request/5` for more detailed information.
  """
  @spec post(pid, String.t, binary, API.headers, Keyword.t) :: {:ok, %{}} | {:error, HTTPoison.Error.t}
  def post(pid, url, body \\ [], headers \\ [], options \\ []) do
    GenServer.call(pid, {:post, url, body, headers, options})
  end

  @doc """
  Same as `post/5` but raises `HTTPoison.Error` if an error occurs during the
  request.
  """
  @spec post!(pid, String.t, binary, API.headers, Keyword.t) :: %{}
  def post!(pid, url, body, headers \\ [], options \\ []) do
    case post(pid, url, body, headers, options) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Streams data from the given url.

  Returns `{:ok, stage}` if the request is successful, `{:error, reason}`
  otherwise.
  """
  @spec stage(pid, Atom.t, String.t, binary, API.headers, Keyword.t) :: {:ok, Stream.t} | {:error, HTTPoison.Error.t}
  def stage(pid, method, url, body \\ [], headers \\ [], options \\ []) do
    {:ok, stage} = Stream.start_link()
    options = Keyword.merge(options, hackney: [stream_to: stage, async: :once], recv_timeout: :infinity)
    case GenServer.call(pid, {method, url, body, headers, options}) do
      {:ok, %HTTPoison.AsyncResponse{}} ->
        {:ok, stage}
      {:error, error} ->
        Stream.stop(stage)
        {:error, error}
    end
  end

  @doc """
  Same as `stage/6` but raises `HTTPoison.Error` if an error occurs during the
  request.
  """
  @spec stage!(pid, Atom.t, String.t, binary, API.headers, Keyword.t) :: Stream.t
  def stage!(pid, method, url, body \\ [], headers \\ [], options \\ []) do
    case stage(pid, method, url, body, headers, options) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def init(nil) do
    case API.get_token() do
      {:ok, token} -> {:ok, token}
      {:error, error} -> {:stop, error.reason}
    end
  end

  def init({username, password}) do
    case API.get_token(username, password) do
      {:ok, token} -> {:ok, token}
      {:error, error} -> {:stop, error.reason}
    end
  end

  def handle_call({method, url, body, headers, options}, _from, token) do
    case API.request(method, url, body, headers, [{:auth, token} | options]) do
      {:ok, %HTTPoison.Response{body: body}} -> {:reply, {:ok, body}, token}
      {:ok, response} -> {:reply, {:ok, response}, token}
      {:error, error} -> {:reply, {:error, error}, token}
    end
  end

  @doc false
  defmacro __using__(_options) do
    quote do
      @doc """
      Starts the process linked to the current process.
      """
      @spec start_link(Keyword.t) :: GenServer.on_start
      def start_link(options \\ []) do
        Twittex.Client.Base.start_link(Dict.put_new(options, :name, __MODULE__))
      end

      defp get(url, headers \\ [], options \\ []) do
        Twittex.Client.Base.get(__MODULE__, url, headers, options)
      end

      defp get!(url, headers \\ [], options \\ []) do
        Twittex.Client.Base.get!(__MODULE__, url, headers, options)
      end

      defp post(url, body \\ [], headers \\ [], options \\ []) do
        Twittex.Client.Base.post(__MODULE__, url, body, headers, options)
      end

      defp post!(url, body \\ [], headers \\ [], options \\ []) do
        Twittex.Client.Base.post!(__MODULE__, url, body, headers, options)
      end

      defp stage(method, url, body \\ [], headers \\ [], options \\ []) do
        Twittex.Client.Base.stage(__MODULE__, method, url, body, headers, options)
      end

      defp stage!(method, url, body \\ [], headers \\ [], options \\ []) do
        Twittex.Client.Base.stage!(__MODULE__, method, url, body, headers, options)
      end
    end
  end
end
