# Model presets. Pick one by name in private.nix: model = "qwen4b";
{
  qwen4b = {
    file  = "Qwen3.5-4B-Q6_K.gguf";
    url   = "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q6_K.gguf";
    flags = "-c 32768 --parallel 1 --cache-ram 1024 --flash-attn on --no-mmap --jinja -ngl 99 -t 4 -ctk q8_0 -ctv q8_0 --reasoning-budget 0 --temp 0.7 --top-p 0.8 --top-k 20";
  };

  # Ornith-1.5-9B (MIT), reasoning model; sampling from its model card (general tasks)
  ornith9b = {
    file  = "Ornith-1.5-9B-Q4_K_M.gguf";
    url   = "https://huggingface.co/bartowski/Ornith-1.5-9B-GGUF/resolve/main/Ornith-1.5-9B-Q4_K_M.gguf";
    flags = "-c 32768 --parallel 1 --cache-ram 1024 --flash-attn on --no-mmap --jinja -ngl 99 -t 4 -ctk q8_0 -ctv q8_0 --reasoning-budget 0 --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 1.5";
  };

  # Same model with thinking on: slower, better on hard questions
  ornith9b-think = {
    file  = "Ornith-1.5-9B-Q4_K_M.gguf";
    url   = "https://huggingface.co/bartowski/Ornith-1.5-9B-GGUF/resolve/main/Ornith-1.5-9B-Q4_K_M.gguf";
    flags = "-c 32768 --parallel 1 --cache-ram 1024 --flash-attn on --no-mmap --jinja -ngl 99 -t 4 -ctk q8_0 -ctv q8_0 --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 1.5";
  };

  # Template: copy, rename, fill in
  # mymodel = {
  #   file  = "Some-Model-Q4_K_M.gguf";
  #   url   = "https://huggingface.co/<org>/<repo>/resolve/main/Some-Model-Q4_K_M.gguf";
  #   flags = "-c 16384 --flash-attn on --no-mmap --jinja -ngl 99 -t 4";
  # };
}
