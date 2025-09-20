import { TRPCError } from "@trpc/server";
import { z } from "zod";
import { companyProcedure, createRouter } from "@/trpc";
import { company_administrator_cap_tables_url } from "@/utils/routes";

// Base investor schema (for SAFE investments and option pools)
const baseInvestorSchema = z.object({
  name: z.string(),
  sharesByClass: z.record(z.string(), z.number()).optional(),
  optionsByStrike: z.record(z.string(), z.number()).optional(),
});

// Full investor schema (for actual investors with IDs)
const fullInvestorSchema = baseInvestorSchema.extend({
  id: z.string(),
  userId: z.string().optional(),
  outstandingShares: z.number().optional(),
  totalOptions: z.number().optional(),
  fullyDilutedShares: z.number().optional(),
  email: z.string().optional(),
});

// Union schema for all investor types
const capTableInvestorSchema = z.union([
  fullInvestorSchema,
  baseInvestorSchema.extend({
    fullyDilutedShares: z.number().optional(),
  }),
]);

const shareClassSchema = z.object({
  id: z.string(),
  name: z.string(),
  outstandingShares: z.number(),
  fullyDilutedShares: z.number(),
});

const optionPoolSchema = z.object({
  name: z.string(),
  availableShares: z.number(),
});

const capTableResponseSchema = z.object({
  investors: z.array(capTableInvestorSchema),
  fullyDilutedShares: z.number(),
  outstandingShares: z.number(),
  optionPools: z.array(optionPoolSchema),
  shareClasses: z.array(shareClassSchema),
  allShareClasses: z.array(z.string()),
  exercisePrices: z.array(z.string()),
});

export const capTableRouter = createRouter({
  show: companyProcedure
    .input(z.object({ newSchema: z.boolean().optional() }))
    .output(capTableResponseSchema)
    .query(async ({ ctx, input }) => {
      const isAdminOrLawyer = !!(ctx.companyAdministrator || ctx.companyLawyer);
      if (!ctx.company.equityEnabled || !(isAdminOrLawyer || ctx.companyInvestor))
        throw new TRPCError({ code: "FORBIDDEN" });

      const url = new URL(company_administrator_cap_tables_url(ctx.company.externalId));
      if (input.newSchema) {
        url.searchParams.set("new_schema", "true");
      }

      const response = await fetch(url.toString(), {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
          ...ctx.headers,
        },
      });

      if (!response.ok) {
        throw new TRPCError({
          code: "INTERNAL_SERVER_ERROR",
          message: "Failed to fetch cap table data",
        });
      }
      return capTableResponseSchema.parse(await response.json());
    }),

  create: companyProcedure
    .input(
      z.object({
        investors: z.array(
          z.object({
            userId: z.string(),
            shares: z.number().positive(),
          }),
        ),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      if (!ctx.companyAdministrator) throw new TRPCError({ code: "FORBIDDEN" });
      if (!ctx.company.equityEnabled) throw new TRPCError({ code: "FORBIDDEN", message: "Equity must be enabled" });

      const response = await fetch(company_administrator_cap_tables_url(ctx.company.externalId), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...ctx.headers,
        },
        body: JSON.stringify({
          cap_table: {
            investors: input.investors,
          },
        }),
      });

      if (!response.ok) {
        const errorSchema = z.object({
          errors: z.array(z.string()).optional(),
        });
        const errorData = errorSchema.parse(await response.json().catch(() => ({})));
        throw new TRPCError({
          code: "BAD_REQUEST",
          message: errorData.errors?.join(", ") || "Failed to create cap table",
        });
      }

      return { success: true };
    }),
});
