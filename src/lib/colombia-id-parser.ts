/**
 * Colombia ID (Cédula de Ciudadanía) PDF417 Barcode Parser
 * 
 * Parses the raw string from the PDF417 barcode found on the back
 * of Colombian cédula de ciudadanía cards.
 * 
 * The barcode format uses fixed-width fields with a "PubDSK_" marker.
 */

export interface ColombianIdData {
  source: 'pdf417';
  firstName: string;
  middleName: string;
  lastName: string;
  secondLastName: string;
  birthDate: string;
  bloodType: string;
  gender: string;
  documentInfo: {
    documentNumber: string;
    afisCode: string;
    fingerCard: string;
  };
}

/**
 * Decode the raw PDF417 barcode string from a Colombian cédula de ciudadanía.
 * Returns null if the string does not contain the expected PubDSK_ marker.
 */
export function decodeColombianPdf417(raw: string): ColombianIdData | null {
  if (!raw.includes('PubDSK_')) {
    return null;
  }

  // Ensure the string is long enough for the basic fields
  if (raw.length < 170) {
    return null;
  }

  const afisCode = raw.substring(2, 10).trim();
  const fingerCard = raw.substring(40, 48).trim();
  const documentNumber = raw.substring(48, 58).replace(/^0+/, '');
  const lastName = raw.substring(58, 80).trim().replace(/\0+$/, '');
  const secondLastName = raw.substring(81, 104).trim().replace(/\0+$/, '');
  const firstName = raw.substring(104, 127).trim().replace(/\0+$/, '');
  let middleName = raw.substring(127, 150).trim().replace(/\0+$/, '');
  
  if (middleName.endsWith('-') || middleName.endsWith('+')) {
    middleName = '';
  }

  const gender = raw.substring(151, 152);
  const year = raw.substring(152, 156);
  const month = raw.substring(156, 158);
  const day = raw.substring(158, 160);
  const birthDate = `${day}-${month}-${year}`;
  const bloodType = raw.substring(166, 168).trim();

  return {
    source: 'pdf417',
    firstName,
    middleName,
    lastName,
    secondLastName,
    birthDate,
    bloodType,
    gender,
    documentInfo: {
      documentNumber,
      afisCode,
      fingerCard,
    },
  };
}

/**
 * Attempt to parse a PDF417 barcode string using multiple strategies.
 * Tries the standard PubDSK_ format first, then falls back to
 * common semicolon-delimited and alternate formats.
 */
export function parseBarcodeString(raw: string): ColombianIdData | null {
  // Strategy 1: Standard PubDSK_ format
  const standard = decodeColombianPdf417(raw);
  if (standard) return standard;

  // Strategy 2: Semicolon-delimited format (CC;number;lastName;firstName;...)
  if (raw.startsWith('CC;') || raw.includes(';')) {
    const parts = raw.split(';');
    if (parts.length >= 4) {
      return {
        source: 'pdf417',
        firstName: parts[3] || '',
        middleName: parts[4] || '',
        lastName: parts[2] || '',
        secondLastName: '',
        birthDate: parts[5] || '',
        bloodType: parts[6] || '',
        gender: parts[7] || '',
        documentInfo: {
          documentNumber: parts[1] || '',
          afisCode: '',
          fingerCard: '',
        },
      };
    }
  }

  // Strategy 3: Try to extract document number and name from any format
  const ccMatch = raw.match(/(\d{6,12})/);
  const nameMatch = raw.match(/([A-ZÁÉÍÓÚÑ]+)\s+([A-ZÁÉÍÓÚÑ]+)/);
  
  if (ccMatch || nameMatch) {
    return {
      source: 'pdf417',
      firstName: nameMatch ? nameMatch[2] : '',
      middleName: '',
      lastName: nameMatch ? nameMatch[1] : '',
      secondLastName: '',
      birthDate: '',
      bloodType: '',
      gender: '',
      documentInfo: {
        documentNumber: ccMatch ? ccMatch[1] : '',
        afisCode: '',
        fingerCard: '',
      },
    };
  }

  return null;
}
