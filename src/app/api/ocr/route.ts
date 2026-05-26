import { NextRequest, NextResponse } from 'next/server';
import ZAI from 'z-ai-web-dev-sdk';

interface OcrResult {
  documentNumber: string;
  fullName: string;
  rawText: string;
  confidence: 'high' | 'medium' | 'low';
}

/**
 * POST /api/ocr
 * 
 * Uses Vision AI to read the FRONT of a Colombian cédula de ciudadanía.
 * Extracts: document number (no punctuation), full name.
 * Returns raw text and parsed fields.
 */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { image } = body as { image: string };

    if (!image) {
      return NextResponse.json(
        { error: 'No se proporcionó imagen' },
        { status: 400 }
      );
    }

    const zai = await ZAI.create();

    const response = await zai.chat.completions.create({
      messages: [
        {
          role: 'system',
          content: `Eres un experto en leer cédulas de ciudadanía colombianas. Tu ÚNICO trabajo es leer la PARTE FRONTAL de la cédula.

La parte frontal de la cédula colombiana contiene:
- El título "REPÚBLICA DE COLOMBIA" o "CÉDULA DE CIUDADANÍA"
- El número de cédula (documento de identidad) - puede tener puntos, comas o espacios (ej: "1.234.567.890")
- Los nombres completos de la persona
- Fecha y lugar de nacimiento
- Sexo (M/F)
- Grupo sanguíneo

INSTRUCCIONES CRÍTICAS:
1. Busca el NÚMERO DE CÉDULA / NÚMERO DE DOCUMENTO. Es el número más prominente en la tarjeta.
2. Busca el NOMBRE COMPLETO de la persona. Suele estar en mayúsculas.
3. Si NO puedes ver claramente un número de documento, responde con documentNumber vacío.
4. El número de documento NO debe tener puntos, comas ni espacios - solo dígitos.

Responde SIEMPRE en formato JSON con estos campos EXACTOS:
{
  "documentNumber": "1234567890",
  "fullName": "JUAN CARLOS PÉREZ GARCÍA",
  "rawText": "todo el texto visible línea por línea",
  "confidence": "high"
}

- documentNumber: SOLO dígitos, sin puntos, comas, espacios ni guiones. Si no lo encuentras, déjalo vacío "".
- fullName: El nombre completo tal como aparece en la cédula, en mayúsculas.
- rawText: Todo el texto visible transcrito línea por línea.
- confidence: "high" si estás seguro del número, "medium" si hay dudas, "low" si apenas puedes leer.

NO inventes datos. Si no puedes leer algo, déjalo vacío.`
        },
        {
          role: 'user',
          content: [
            {
              type: 'image_url',
              image_url: { url: image },
            },
            {
              type: 'text',
              text: 'Lee la parte frontal de esta cédula de ciudadanía colombiana. Extrae el número de documento (sin puntos ni comas ni espacios) y el nombre completo. Si no puedes ver un número de documento claro, responde con documentNumber vacío. Responde solo en JSON.',
            },
          ],
        },
      ],
      max_tokens: 1000,
      temperature: 0.05,
    });

    const aiContent = response.choices?.[0]?.message?.content || '';

    let result: OcrResult;
    try {
      // Try to extract JSON from the AI response
      const jsonMatch =
        aiContent.match(/```(?:json)?\s*([\s\S]*?)```/) ||
        aiContent.match(/(\{[\s\S]*\})/);
      const jsonStr = jsonMatch ? jsonMatch[1] : aiContent;
      result = JSON.parse(jsonStr);
    } catch {
      // If JSON parsing fails, try to extract data from raw text
      result = {
        documentNumber: '',
        fullName: '',
        rawText: aiContent,
        confidence: 'low',
      };
    }

    // Clean the document number: remove all non-digit characters
    if (result.documentNumber) {
      result.documentNumber = result.documentNumber.replace(/[^0-9]/g, '');
    }

    // Validate: Colombian cédula numbers are typically 8-11 digits
    if (result.documentNumber && (result.documentNumber.length < 6 || result.documentNumber.length > 15)) {
      result.confidence = 'low';
    }

    return NextResponse.json({
      success: true,
      data: result,
    });
  } catch (error) {
    console.error('OCR error:', error);
    return NextResponse.json(
      { error: 'Error al procesar la imagen con OCR', details: String(error) },
      { status: 500 }
    );
  }
}
