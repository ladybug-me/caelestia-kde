import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';

import { repoDocs } from './loaders/repo-docs';

/**
 * The docs collection is not authored here: it is the repository's markdown,
 * read at build time. See src/loaders/repo-docs.ts for which documents are used
 * and how their links are rewritten.
 */
const docs = defineCollection({
    loader: repoDocs(),
    schema: z.object({
        title: z.string(),
        description: z.string(),
        /** Sidebar grouping. */
        group: z.string(),
        /** Sort order within the group. */
        order: z.number(),
        /** The file this page comes from, shown at the foot of the page. */
        source: z.string(),
    }),
});

export const collections = { docs };
