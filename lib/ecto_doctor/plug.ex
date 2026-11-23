if Code.ensure_loaded?(Plug.Conn) do
  defmodule EctoDoctor.Plug do
    @moduledoc """
    Lists the page's N+1 queries in a footer and in the browser console while you develop.

    Add it to the browser pipeline in dev only since the footer shows SQL and file paths to anyone who loads the page.

        if Application.compile_env(:my_app, :dev_routes) do
          plug EctoDoctor.Plug
        end

    It shows nothing until N+1 detection is attached, so attach it when the app starts in dev.

        # lib/my_app/application.ex in start/2
        if Application.get_env(:my_app, :dev_routes) == true and
             Code.ensure_loaded?(EctoDoctor.RepeatedQueries) do
          EctoDoctor.RepeatedQueries.attach(repo: MyApp.Repo)
        end

    The footer lists every N+1 on the page, even ones the baseline file knows.

    Pass `nonce: :csp_nonce` when a content security policy needs a nonce from that assign.
    """

    @behaviour Plug

    import Plug.Conn

    require EEx

    alias EctoDoctor.RepeatedQueries

    # The colours and fonts follow the Phoenix error page so the bar feels part of the dev tools
    # The style and the close button live in tags that carry the nonce
    # so a strict content security policy that blocks inline attributes still allows them
    @footer ~S"""
    <style<%= nonce %>>
      #ecto-doctor { --ed-primary: #4e2a8e; --ed-accent: #607080; --ed-text: #203040; --ed-line: #e5e7eb; --ed-bar: #f9f9fa; --ed-panel: #ffffff; --ed-code: #f0f4fa; position: fixed; left: 0; right: 0; bottom: 0; z-index: 2147483000; color: var(--ed-text); background: var(--ed-panel); border-top: 1px solid var(--ed-line); font: 13px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; text-align: left; color-scheme: light }
      @media (prefers-color-scheme: dark) {
        #ecto-doctor { --ed-primary: #9d86d2; --ed-accent: #9aa5b1; --ed-text: #e5e5e5; --ed-line: #404040; --ed-bar: #2a2a2a; --ed-panel: #1c1c1c; --ed-code: #2d333b; color-scheme: dark }
      }
      #ecto-doctor * { box-sizing: border-box; margin: 0; padding: 0; font: inherit; color: inherit }
      #ecto-doctor summary { display: flex; align-items: baseline; gap: 16px; padding: 6px 16px; background: var(--ed-bar); cursor: pointer; list-style: none; user-select: none }
      #ecto-doctor summary::-webkit-details-marker { display: none }
      #ecto-doctor summary::before { content: "\25B8"; color: var(--ed-accent); width: 8px }
      #ecto-doctor[open] summary::before { content: "\25BE" }
      #ecto-doctor .ed-name { font-weight: 700; color: var(--ed-primary) }
      #ecto-doctor .ed-page, #ecto-doctor .ed-where small, #ecto-doctor .ed-sql { font-family: menlo, consolas, monospace; font-size: 12px }
      #ecto-doctor .ed-page { color: var(--ed-accent); flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap }
      #ecto-doctor button { background: none; border: 0; color: var(--ed-accent); cursor: pointer }
      #ecto-doctor button:hover { color: var(--ed-text); text-decoration: underline }
      #ecto-doctor ol { list-style: none; max-height: 45vh; overflow: auto; border-top: 1px solid var(--ed-line) }
      #ecto-doctor li { padding: 12px 16px 14px; border-bottom: 1px solid var(--ed-line) }
      #ecto-doctor li:last-child { border-bottom: 0 }
      #ecto-doctor .ed-head { display: flex; align-items: baseline; gap: 12px }
      #ecto-doctor .ed-times { font-weight: 700; color: var(--ed-primary); min-width: 2.5em }
      #ecto-doctor .ed-where { flex: 1; min-width: 0; overflow-wrap: anywhere }
      #ecto-doctor .ed-where small { color: var(--ed-accent); margin-left: 8px }
      #ecto-doctor .ed-ms { color: var(--ed-accent); white-space: nowrap }
      #ecto-doctor .ed-sql { display: block; margin: 8px 0 0 calc(2.5em + 12px); padding: 8px 10px; max-height: 120px; overflow: auto; background: var(--ed-code); border-radius: 3px; white-space: pre-wrap; overflow-wrap: anywhere }
      #ecto-doctor .ed-fix { margin: 6px 0 0 calc(2.5em + 12px) }
      #ecto-doctor .ed-fix b { font-weight: 700; color: var(--ed-primary); margin-right: 6px }
    </style>
    <details id="ecto-doctor" data-messages="<%= escape(messages) %>">
      <summary>
        <span class="ed-name">Ecto Doctor</span>
        <span><%= title %></span>
        <span class="ed-page"><%= escape(page) %></span>
        <button type="button">Close</button>
      </summary>
      <ol>
      <%= for finding <- findings do %>
        <li>
          <div class="ed-head">
            <span class="ed-times"><%= finding.count %>&times;</span>
            <span class="ed-where"><%= where(finding) %></span>
            <span class="ed-ms"><%= Float.round(finding.duration_ms, 1) %> ms</span>
          </div>
          <code class="ed-sql"><%= escape(finding.sql) %></code>
          <%= if finding.fix do %><p class="ed-fix"><b>Fix</b><%= escape(finding.fix) %></p><% end %>
        </li>
      <% end %>
      </ol>
    </details>
    <script<%= nonce %>>
      (function () {
        var footer = document.getElementById("ecto-doctor")
        footer.querySelector("button").addEventListener("click", function (event) {
          event.preventDefault()
          footer.remove()
        })
        JSON.parse(footer.dataset.messages).forEach(function (message) { console.warn(message) })
      })()
    </script>
    """

    EEx.function_from_string(:defp, :render, @footer, [
      :findings,
      :title,
      :page,
      :messages,
      :nonce
    ])

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, opts) do
      if RepeatedQueries.attached?() do
        owner = RepeatedQueries.start_page("#{conn.method} #{conn.request_path}")
        register_before_send(conn, &add_footer(&1, owner, opts))
      else
        conn
      end
    end

    # Detaching while a request runs takes the tables away so the page is left alone then
    defp add_footer(conn, owner, opts) do
      if RepeatedQueries.attached?() do
        findings = RepeatedQueries.peek(owner)
        RepeatedQueries.finish(owner)
        footer(conn, findings, opts)
      else
        conn
      end
    end

    defp footer(conn, findings, opts) do
      if findings != [] and html?(conn) and body?(conn) and not compressed?(conn) do
        page = "#{conn.method} #{conn.request_path}"
        %{conn | resp_body: insert_footer(conn.resp_body, findings, page, nonce(conn, opts))}
      else
        conn
      end
    end

    defp nonce(conn, opts) do
      case Keyword.fetch(opts, :nonce) do
        {:ok, assign} -> conn.assigns[assign]
        :error -> nil
      end
    end

    # A streamed or file response has no body to add to
    defp body?(conn), do: is_binary(conn.resp_body) or is_list(conn.resp_body)

    # A gzipped body can't take extra bytes in the middle
    defp compressed?(conn), do: get_resp_header(conn, "content-encoding") != []

    defp html?(conn) do
      conn
      |> get_resp_header("content-type")
      |> Enum.any?(&String.starts_with?(&1, "text/html"))
    end

    defp insert_footer(body, findings, page, nonce) do
      count = length(findings)
      title = if count == 1, do: "1 N+1 query", else: "#{count} N+1 queries"

      messages = JSON.encode!(Enum.map(findings, &"N+1 query ran #{&1.count} times. #{&1.sql}"))
      nonce = if nonce, do: " nonce=\"#{escape(nonce)}\"", else: ""

      footer = render(findings, title, page, messages, nonce)

      body
      |> IO.iodata_to_binary()
      |> insert_before_last_body_end(footer)
    end

    # A </body> can also sit inside a script or a comment so only the last one is the page's end
    defp insert_before_last_body_end(body, footer) do
      case :binary.matches(body, ["</body>", "</BODY>", "</Body>"]) do
        [] ->
          body

        matches ->
          {at, _length} = List.last(matches)
          binary_part(body, 0, at) <> footer <> binary_part(body, at, byte_size(body) - at)
      end
    end

    defp where(%{origin: nil}), do: ""

    defp where(%{origin: {module, fun, arity, file, line}}) do
      escape("#{inspect(module)}.#{fun}/#{arity}") <>
        "<small>" <> escape("#{file}:#{line}") <> "</small>"
    end

    defp escape(text), do: text |> Plug.HTML.html_escape() |> IO.iodata_to_binary()
  end
end
