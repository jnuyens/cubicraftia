# TripoSR pipeline for Cubicraftia creature meshes

## Install (already done; one-time)

Lives outside the repo at `/Users/jnuyens/ai-tools/TripoSR` (15 GB venv + weights).
Setup steps performed:

```bash
cd /Users/jnuyens/ai-tools
git clone --depth 1 https://github.com/VAST-AI-Research/TripoSR.git
cd TripoSR
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install torch numpy pillow einops omegaconf trimesh xatlas huggingface-hub
pip install "transformers==4.35.0"           # newer transformers breaks the checkpoint
pip install "rembg[cpu]"                      # background-removal model + onnxruntime
pip install scikit-build-core
CMAKE_PREFIX_PATH="$(python -c 'import torch, os; print(os.path.dirname(torch.__file__))')" \
  pip install --force-reinstall git+https://github.com/tatsy/torchmcubes.git
```

License: TripoSR is MIT (Tripo AI + Stability AI). Outputs can ship in
Cubicraftia (GPL-3.0-or-later).

## Run on a single reference image

```bash
cd /Users/jnuyens/ai-tools/TripoSR
source venv/bin/activate
python run.py /path/to/reference.png --output-dir /path/to/out --device mps --model-save-format glb
```

Per-asset timing on M4 (MPS): ~35s model, ~75s mesh extraction, ~270ms export
≈ 2 min total. Output: `out/0/mesh.glb` + `out/0/input.png` (the post-rembg input).

## Reference image requirements

TripoSR works best with:
- 512×512 or 1024×1024 clean object on white background
- Single subject, centred
- Top-down/three-quarter view shows the silhouette best
- No background patterns (the brick-pattern title bg would confuse it)

Generate references for the 23 creatures via either:
- (A) PIL stylised silhouettes (use Cubicraftia palette, draw a clear creature outline)
- (B) Render existing primitive meshes from `assets/meshes/creatures/` at front view in Blender
- (C) Open-license reference photos from Wikimedia (best quality, real animal anatomy)

After TripoSR generates a mesh, apply Cubicraftia palette materials in Blender
post-processing (per model-bible §1.5 — matte, no specular, soft chunky silhouette).

## Batch script (TODO)

To process all 23 creatures: write a wrapper that iterates the creature list,
runs TripoSR per reference image, moves output to `assets/meshes/creatures/`,
applies palette materials via a Blender post-process pass.

Verified: chair.png example produced clean mesh.obj in 2:19 wall time on M4.
