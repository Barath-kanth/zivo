import { useMockAi, gcpProjectId } from '../config.js';
import { generateGeminiJson } from '../gemini.js';

export type DynamicFieldType = 'number' | 'text' | 'select' | 'boolean' | 'date';

export type DynamicPricingField = {
  id: string;
  label: string;
  type: DynamicFieldType;
  required: boolean;
  unit?: string;
  options?: string[];
  help?: string;
  default_value?: string | number | boolean;
};

export type PricingFieldsResult = {
  pillar: 'pricing_fields';
  mode: 'mock' | 'gemini';
  category: string;
  /** Short human line — no model brand names. */
  headline: string;
  fields: DynamicPricingField[];
  /** Why these fields matter for this task (user-facing, plain language). */
  note: string;
};

function mockFieldsForCategory(category: string, title: string, description: string): DynamicPricingField[] {
  const text = `${title} ${description} ${category}`.toLowerCase();

  if (
    category === 'documentWork' ||
    /paper|essay|thesis|write|document|research|plagiar/.test(text)
  ) {
    return [
      {
        id: 'word_count',
        label: 'Approximate word count',
        type: 'number',
        required: true,
        unit: 'words',
        default_value: 1500,
        help: 'Rough length of the document',
      },
      {
        id: 'page_count',
        label: 'Number of pages',
        type: 'number',
        required: true,
        unit: 'pages',
        default_value: 8,
      },
      {
        id: 'needs_plagiarism_check',
        label: 'Needs plagiarism check',
        type: 'boolean',
        required: true,
        default_value: true,
      },
      {
        id: 'citation_style',
        label: 'Citation style',
        type: 'select',
        required: false,
        options: ['None', 'APA', 'MLA', 'Harvard', 'IEEE'],
        default_value: 'APA',
      },
      {
        id: 'deadline_at',
        label: 'Complete before',
        type: 'date',
        required: true,
      },
    ];
  }

  if (category === 'homeCleaning' || /clean|mop|rooms|sq ?ft|square/.test(text)) {
    return [
      {
        id: 'room_count',
        label: 'Number of rooms',
        type: 'number',
        required: true,
        default_value: 2,
      },
      {
        id: 'square_feet',
        label: 'Approximate area',
        type: 'number',
        required: true,
        unit: 'sq ft',
        default_value: 800,
      },
      {
        id: 'includes_bathroom',
        label: 'Includes bathroom deep-clean',
        type: 'boolean',
        required: true,
        default_value: true,
      },
      {
        id: 'supplies_provided',
        label: 'Cleaning supplies provided',
        type: 'boolean',
        required: false,
        default_value: true,
      },
      {
        id: 'deadline_at',
        label: 'Complete before',
        type: 'date',
        required: true,
      },
    ];
  }

  if (category === 'movingHelp' || /sofa|couch|heavy|stairs|move/.test(text)) {
    return [
      {
        id: 'item_count',
        label: 'Number of items to move',
        type: 'number',
        required: true,
        default_value: 3,
      },
      {
        id: 'heaviest_kg',
        label: 'Heaviest item weight',
        type: 'number',
        required: true,
        unit: 'kg',
        default_value: 40,
      },
      {
        id: 'flights_of_stairs',
        label: 'Flights of stairs',
        type: 'number',
        required: true,
        default_value: 2,
      },
      {
        id: 'helpers_needed',
        label: 'People needed',
        type: 'number',
        required: true,
        default_value: 2,
      },
      {
        id: 'deadline_at',
        label: 'Complete before',
        type: 'date',
        required: true,
      },
    ];
  }

  if (
    category === 'groceryRun' ||
    category === 'errandRun' ||
    /deliver|delivery|parcel|courier|drop/.test(text)
  ) {
    return [
      {
        id: 'travel_km',
        label: 'Travel / delivery distance',
        type: 'number',
        required: true,
        unit: 'km',
        default_value: 1.5,
      },
      {
        id: 'stops_count',
        label: 'Number of stops',
        type: 'number',
        required: true,
        default_value: 1,
      },
      {
        id: 'package_weight_kg',
        label: 'Package weight',
        type: 'number',
        required: false,
        unit: 'kg',
        default_value: 2,
      },
      {
        id: 'needs_vehicle',
        label: 'Needs bike or vehicle',
        type: 'boolean',
        required: true,
        default_value: false,
      },
      {
        id: 'deadline_at',
        label: 'Complete before',
        type: 'date',
        required: true,
      },
    ];
  }

  if (category === 'queueStanding' || /queue|line|bakery/.test(text)) {
    return [
      {
        id: 'expected_wait_minutes',
        label: 'Expected wait time',
        type: 'number',
        required: true,
        unit: 'min',
        default_value: 30,
      },
      {
        id: 'outdoor',
        label: 'Mostly outdoor wait',
        type: 'boolean',
        required: false,
        default_value: true,
      },
      {
        id: 'deadline_at',
        label: 'Must be done by',
        type: 'date',
        required: true,
      },
    ];
  }

  // Generic neighborhood favor
  return [
    {
      id: 'effort_level',
      label: 'How demanding is this?',
      type: 'select',
      required: true,
      options: ['Light', 'Moderate', 'Demanding'],
      default_value: 'Moderate',
    },
    {
      id: 'travel_km',
      label: 'Travel distance (if any)',
      type: 'number',
      required: false,
      unit: 'km',
      default_value: 0,
    },
    {
      id: 'deadline_at',
      label: 'Complete before',
      type: 'date',
      required: true,
    },
  ];
}

/** AI (or category mock) designs the pricing questions for this specific task. */
export async function generatePricingFields(input: {
  title: string;
  description: string;
  category: string;
}): Promise<PricingFieldsResult> {
  const title = input.title.trim() || 'Task';
  const description = input.description.trim();
  const category = input.category || 'other';

  const fallback: PricingFieldsResult = {
    pillar: 'pricing_fields',
    mode: 'mock',
    category,
    headline: 'A few details so we can price this fairly',
    note: 'Answers depend on what you asked for — not a one-size form.',
    fields: mockFieldsForCategory(category, title, description),
  };

  if (useMockAi || !gcpProjectId || gcpProjectId === 'your-gcp-project-id') {
    return fallback;
  }

  try {
    const g = await generateGeminiJson<{
      headline?: string;
      note?: string;
      fields: DynamicPricingField[];
    }>(
      `You design a short pricing questionnaire for a Sri Lanka neighborhood task app (Zivo).
Do NOT mention AI, models, or brand names in any string.

Given this task, invent ONLY the fields a human operator would ask to price it fairly.
Different task types need different questions:
- Document / writing → word count, pages, plagiarism, citation style (NOT "hours of help" unless tutoring)
- Cleaning → rooms, square feet, bathrooms, supplies
- Moving → item count, weight kg, stairs, helpers needed
- Delivery / errand → distance km, stops, package weight, vehicle
- Queue → expected wait minutes
Never ask generic "difficulty" or "physical effort" enums.
Always include a "deadline_at" date field (required) labeled like "Complete before".
Max 6 fields. Use simple labels a Colombo user understands.
Field types: number | text | select | boolean | date
ids: snake_case English.

Title: ${JSON.stringify(title)}
Category: ${JSON.stringify(category)}
Description: ${JSON.stringify(description)}

Return ONLY JSON:
{
  "headline":"short heading",
  "note":"one plain sentence",
  "fields":[{"id":"...","label":"...","type":"number","required":true,"unit":"optional","options":["for select"],"help":"optional","default_value":...}]
}`,
    );

    const fields = Array.isArray(g.fields)
      ? g.fields.filter((f) => f?.id && f?.label && f?.type).slice(0, 8)
      : [];
    if (!fields.length) return fallback;

    // Ensure deadline exists
    if (!fields.some((f) => f.id === 'deadline_at' || f.type === 'date')) {
      fields.push({
        id: 'deadline_at',
        label: 'Complete before',
        type: 'date',
        required: true,
      });
    }

    return {
      pillar: 'pricing_fields',
      mode: 'gemini',
      category,
      headline: (g.headline || fallback.headline).replace(/gemini/gi, 'fair'),
      note: (g.note || fallback.note).replace(/gemini/gi, 'our'),
      fields,
    };
  } catch {
    return fallback;
  }
}
