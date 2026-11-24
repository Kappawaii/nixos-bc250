# Model presets. Pick one by name in private.nix: model = "qwen4b";
{
  qwen4b = {
    file  = "Qwen3.5-4B-Q6_K.gguf";
    url   = "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q6_K.gguf";
    flags = "-c 32768 --parallel 1 --cache-ram 1024 --flash-attn on --no-mmap --jinja -ngl 99 -t 4 -ctk q8_0 -ctv q8_0 --reasoning-budget 0 --temp 0.7 --top-p 0.8 --top-k 20";
  };

  # Template: copy, rename, fill in
  # mymodel = {
  #   file  = "Some-Model-Q4_K_M.gguf";
  #   url   = "https://huggingface.co/<org>/<repo>/resolve/main/Some-Model-Q4_K_M.gguf";
  #   flags = "-c 16384 --flash-attn on --no-mmap --jinja -ngl 99 -t 4";
  # };
}
