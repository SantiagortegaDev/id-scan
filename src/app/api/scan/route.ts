import { NextRequest, NextResponse } from 'next/server';
import sharp from 'sharp';
import ZAI from 'z-ai-web-dev-sdk';

/**
 * POST /api/scan
 * 
 * Modes:
 * - enhance: Image preprocessing for barcode decoding
 * - analyze: Backend-enhanced images for barcode re-attempt
 * - vlm: Use Vision AI to read the ID card text (most robust fallback)
 */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { image, mode } = body as { image: string; mode?: 'enhance' | 'analyze' | 'vlm' };

    if (!image) {
      return NextResponse.json(
        { error: 'No se proporcionó imagen' },
        { status: 400 }
      );
    }

    // Remove data URL prefix if present
    const base64Data = image.replace(/^data:image\/\w+;base64,/, '');
    const imageBuffer = Buffer.from(base64Data, 'base64');

    // ====== VLM MODE: Use AI Vision to read the ID card ======
    if (mode === 'vlm') {
      try {
        const zai = await ZAI.create();

        // First, try to get the AI to read the barcode data directly
        const barcodeResponse = await zai.chat.completions.create({
          messages: [
            {
              role: 'system',
              content: `Eres un experto en leer cédulas de ciudadanía colombianas. Tu trabajo es extraer la información del reverso de la cédula.

El reverso de la cédula colombiana contiene:
1. Un código de barras PDF417 en la parte inferior que contiene TODA la información
2. Texto impreso con información personal

Si puedes ver el código de barras, intenta describir qué contiene.
Si NO puedes leer el código de barras (es muy pequeño/denso), lee el TEXTO IMPRESO que aparece en la tarjeta.

Responde SIEMPRE en formato JSON con estos campos:
{
  "barcodeReadable": true/false,
  "rawBarcodeContent": "el contenido exacto del código si lo puedes leer, sino cadena vacía",
  "documentNumber": "número de cédula",
  "firstName": "primer nombre",
  "middleName": "segundo nombre (si aparece)",
  "lastName": "primer apellido",
  "secondLastName": "segundo apellido (si aparece)",
  "birthDate": "fecha de nacimiento en formato DD-MM-AAAA",
  "gender": "M o F",
  "bloodType": "grupo sanguíneo (ej: O+, A-)",
  "expiryDate": "fecha de vencimiento si aparece",
  "allVisibleText": "todo el texto visible en la imagen, línea por línea"
}

IMPORTANTE: Si no puedes leer algún campo, déjalo como cadena vacía "". 
Si puedes ver texto impreso en la cédula, extráelo con cuidado.
Los campos más importantes son: documentNumber, firstName, lastName, birthDate.`
            },
            {
              role: 'user',
              content: [
                {
                  type: 'image_url',
                  image_url: {
                    url: image,
                  },
                },
                {
                  type: 'text',
                  text: 'Lee la información de esta cédula de ciudadanía colombiana. Si puedes leer el código de barras PDF417, dame su contenido exacto. Si no puedes leer el código, lee el texto impreso visible en la tarjeta. Responde en formato JSON.',
                },
              ],
            },
          ],
          max_tokens: 2000,
          temperature: 0.1,
        });

        const aiContent = barcodeResponse.choices?.[0]?.message?.content || '';
        
        // Try to extract JSON from the AI response
        let parsedData;
        try {
          // Try to find JSON in the response (may be wrapped in markdown code blocks)
          const jsonMatch = aiContent.match(/```(?:json)?\s*([\s\S]*?)```/) || 
                           aiContent.match(/(\{[\s\S]*\})/);
          const jsonStr = jsonMatch ? jsonMatch[1] : aiContent;
          parsedData = JSON.parse(jsonStr);
        } catch {
          // If JSON parsing fails, return the raw AI response
          parsedData = {
            barcodeReadable: false,
            rawBarcodeContent: '',
            allVisibleText: aiContent,
            documentNumber: '',
            firstName: '',
            middleName: '',
            lastName: '',
            secondLastName: '',
            birthDate: '',
            gender: '',
            bloodType: '',
            expiryDate: '',
          };
        }

        return NextResponse.json({
          success: true,
          source: 'vlm',
          data: parsedData,
          rawAiResponse: aiContent,
        });
      } catch (error) {
        console.error('VLM error:', error);
        return NextResponse.json(
          { error: 'Error al procesar con IA visual', details: String(error) },
          { status: 500 }
        );
      }
    }

    // ====== ENHANCE MODE: Image preprocessing ======
    if (mode === 'enhance') {
      // Strategy 1: Grayscale + high contrast + sharpening
      const enhanced1 = await sharp(imageBuffer)
        .grayscale()
        .normalize()
        .sharpen({ sigma: 1.5, m1: 1, m2: 0.5 })
        .modulate({ brightness: 1.1 })
        .linear(1.8, -(128 * 0.8))
        .jpeg({ quality: 95 })
        .toBuffer();

      // Strategy 2: Binary threshold (black & white)
      const enhanced2 = await sharp(imageBuffer)
        .grayscale()
        .normalize()
        .sharpen({ sigma: 2, m1: 2, m2: 0.5 })
        .threshold(128)
        .jpeg({ quality: 95 })
        .toBuffer();

      // Strategy 3: Resize to 3x for better pixel density on narrow barcodes
      const metadata = await sharp(imageBuffer).metadata();
      const width = metadata.width || 1000;
      const height = metadata.height || 2000;
      
      const enhanced3 = await sharp(imageBuffer)
        .grayscale()
        .normalize()
        .sharpen({ sigma: 1.5, m1: 1, m2: 0.5 })
        .resize(Math.min(width * 3, 6000), Math.min(height * 3, 12000), {
          fit: 'inside',
          kernel: sharp.kernel.lanczos3,
        })
        .jpeg({ quality: 95 })
        .toBuffer();

      // Strategy 4: Aggressive contrast + 3x upscale (for very narrow barcodes)
      const enhanced4 = await sharp(imageBuffer)
        .grayscale()
        .normalize()
        .sharpen({ sigma: 3, m1: 3, m2: 1 })
        .linear(2.5, -(128 * 1.5))
        .resize(Math.min(width * 3, 6000), Math.min(height * 3, 12000), {
          fit: 'inside',
          kernel: sharp.kernel.lanczos3,
        })
        .jpeg({ quality: 95 })
        .toBuffer();

      return NextResponse.json({
        success: true,
        enhancedImages: [
          {
            name: 'high-contrast',
            image: `data:image/jpeg;base64,${enhanced1.toString('base64')}`,
            description: 'Alto contraste y enfoque mejorado',
          },
          {
            name: 'binary-threshold',
            image: `data:image/jpeg;base64,${enhanced2.toString('base64')}`,
            description: 'Umbral binario (blanco y negro)',
          },
          {
            name: 'upscaled-3x',
            image: `data:image/jpeg;base64,${enhanced3.toString('base64')}`,
            description: 'Imagen ampliada 3x con enfoque',
          },
          {
            name: 'aggressive-3x',
            image: `data:image/jpeg;base64,${enhanced4.toString('base64')}`,
            description: 'Contraste agresivo + ampliación 3x',
          },
        ],
      });
    }

    // ====== ANALYZE MODE: Extract barcode region + enhance ======
    if (mode === 'analyze') {
      const meta = await sharp(imageBuffer).metadata();
      const h = meta.height || 2000;
      const w = meta.width || 1000;

      // Extract bottom 40% of the image (barcode is usually at the bottom)
      const barcodeRegion = await sharp(imageBuffer)
        .extract({
          left: 0,
          top: Math.floor(h * 0.6),
          width: w,
          height: Math.floor(h * 0.4),
        })
        .grayscale()
        .normalize()
        .sharpen({ sigma: 2, m1: 2, m2: 0.5 })
        .linear(1.8, -(128 * 0.8))
        .resize(w * 3, Math.floor(h * 0.4) * 3, {
          fit: 'inside',
          kernel: sharp.kernel.lanczos3,
        })
        .jpeg({ quality: 95 })
        .toBuffer();

      // Extract bottom 30% with more aggressive enhancement
      const barcodeRegionAggressive = await sharp(imageBuffer)
        .extract({
          left: 0,
          top: Math.floor(h * 0.7),
          width: w,
          height: Math.floor(h * 0.3),
        })
        .grayscale()
        .normalize()
        .sharpen({ sigma: 3, m1: 3, m2: 1 })
        .linear(2.5, -(128 * 1.5))
        .resize(w * 4, Math.floor(h * 0.3) * 4, {
          fit: 'inside',
          kernel: sharp.kernel.lanczos3,
        })
        .jpeg({ quality: 95 })
        .toBuffer();

      // Full image with max enhancement + 3x upscale
      const fullEnhanced = await sharp(imageBuffer)
        .grayscale()
        .normalize()
        .sharpen({ sigma: 2.5, m1: 2, m2: 0.5 })
        .linear(2.0, -(128 * 1.0))
        .resize(Math.min(w * 3, 6000), Math.min(h * 3, 12000), {
          fit: 'inside',
          kernel: sharp.kernel.lanczos3,
        })
        .jpeg({ quality: 95 })
        .toBuffer();

      return NextResponse.json({
        success: true,
        enhancedImages: [
          {
            name: 'barcode-region-3x',
            image: `data:image/jpeg;base64,${barcodeRegion.toString('base64')}`,
            description: 'Región del código de barras (40% inferior) ampliada 3x',
          },
          {
            name: 'barcode-region-aggressive-4x',
            image: `data:image/jpeg;base64,${barcodeRegionAggressive.toString('base64')}`,
            description: 'Región del código (30% inferior) con contraste agresivo 4x',
          },
          {
            name: 'full-enhanced-3x',
            image: `data:image/jpeg;base64,${fullEnhanced.toString('base64')}`,
            description: 'Imagen completa con máximo realce 3x',
          },
        ],
      });
    }

    return NextResponse.json(
      { error: 'Modo no válido. Use "enhance", "analyze" o "vlm"' },
      { status: 400 }
    );
  } catch (error) {
    console.error('Error processing image:', error);
    return NextResponse.json(
      { error: 'Error al procesar la imagen', details: String(error) },
      { status: 500 }
    );
  }
}
