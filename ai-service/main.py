from pathlib import Path
from uuid import uuid4
import io
from PIL import Image, ImageOps, ImageFilter, ImageDraw
from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from rembg import remove

ROOT = Path(__file__).resolve().parent
MEDIA = ROOT / 'media'
MEDIA.mkdir(exist_ok=True)
app = FastAPI(title='Vastram Product Studio', version='0.3.0')
app.add_middleware(CORSMiddleware, allow_origins=['*'], allow_methods=['*'], allow_headers=['*'])
app.mount('/media', StaticFiles(directory=MEDIA), name='media')


def prepare_cutout(src: Image.Image) -> Image.Image:
    cut = remove(src.convert('RGBA'))
    bbox = cut.getbbox()
    if not bbox:
        raise HTTPException(422, 'No garment foreground was detected. Use a clear photo with one garment.')
    cut = cut.crop(bbox)
    # Tighten transparent edges and remove tiny alpha noise.
    alpha = cut.getchannel('A').point(lambda p: 255 if p > 12 else 0)
    cut.putalpha(alpha)
    return cut


def fit(img, box):
    w, h = img.size
    bw, bh = box
    scale = min(bw / max(w,1), bh / max(h,1), 1.0)
    return img.resize((max(1, int(w*scale)), max(1, int(h*scale))), Image.Resampling.LANCZOS)


def compose(cut: Image.Image, mode: str) -> Image.Image:
    canvas = Image.new('RGBA', (1400, 1400), (248, 247, 244, 255))
    garment = fit(cut, (980, 1050) if mode == 'hanging' else (1050, 1050))
    x = (1400 - garment.width)//2
    y = (1400 - garment.height)//2
    d = ImageDraw.Draw(canvas)
    if mode == 'hanging':
        # Studio hanger presentation; garment pixels are preserved.
        rail_y = 125
        d.rounded_rectangle((370, 85, 1030, 120), radius=14, fill=(48, 48, 48, 255))
        d.line((700, 120, 700, 160), fill=(48,48,48,255), width=10)
        d.arc((660, 140, 740, 220), 195, 345, fill=(48,48,48,255), width=9)
        y = max(y, 225)
    canvas.alpha_composite(garment, (x,y))
    return canvas


def enhance(img):
    rgb = img.convert('RGB')
    rgb = ImageOps.autocontrast(rgb, cutoff=0.4)
    rgb = rgb.filter(ImageFilter.UnsharpMask(radius=1.1, percent=125, threshold=3))
    return rgb

@app.get('/health')
def health():
    return {'ok': True, 'service': 'vastram-product-studio', 'mode': 'local-fallback', 'api_keys_required': False}

@app.post('/api/product-studio/process')
async def process_product(file: UploadFile = File(...), mode: str = Form('hanging')):
    if mode not in {'hanging','flatlay'}:
        raise HTTPException(400, 'mode must be hanging or flatlay')
    raw = await file.read()
    if not raw or len(raw) > 15 * 1024 * 1024:
        raise HTTPException(400, 'Image must be between 1 byte and 15 MB.')
    try:
        src = Image.open(io.BytesIO(raw)).convert('RGBA')
    except Exception:
        raise HTTPException(400, 'Invalid image. Upload JPG, PNG or WEBP.')
    cut = prepare_cutout(src)
    cut_name = f'{uuid4().hex}_cutout.png'
    cut.save(MEDIA / cut_name)
    final = enhance(compose(cut, mode))
    out_name = f'{uuid4().hex}_{mode}.jpg'
    final.save(MEDIA / out_name, quality=95, optimize=True, progressive=True)
    return {
        'ok': True,
        'output_url': f'/media/{out_name}',
        'cutout_url': f'/media/{cut_name}',
        'mode': mode,
        'processing': ['background_removal','garment_foreground','catalog_composition','clarity_enhancement','clean_background','saved'],
        'ai_generation': 'local-safe-fallback',
        'paid_api': False,
    }
