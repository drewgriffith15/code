import pandas as pd
from dataclasses import dataclass
from typing import Dict, List

# ==========================================
# CONFIGURATION & INPUTS
# ==========================================

# CONSTANTS
MONTHS_PER_YEAR = 12

# Standard Pay Periods for 'D' (Semi-monthly)
# This ensures D is calculated on 24 periods regardless of K's schedule.
PAY_PERIODS_D_FIXED = 24 

@dataclass
class IncomeProfile:
    """Class to hold income details for a specific scenario."""
    name: str
    salary_d: float
    salary_k: float
    add_yearly_d: float = 0.0
    add_yearly_k: float = 0.0
    # Pay periods specific to K (Changes from 24 to 26)
    pay_periods_k: int = 24 

# ==========================================
# INPUT SCENARIOS
# ==========================================
scenarios = [
    IncomeProfile(
        name="Current (2025)",
        salary_d=140000.00,
        salary_k=175000.00,
        add_yearly_d=0,
        add_yearly_k=0,
        pay_periods_k=24  # Old schedule: Semi-monthly (24/yr)
    ),
    IncomeProfile(
        name="New Estimates (2026)",
        salary_d=148400.00,
        salary_k=108000.00,
        add_yearly_d=0,
        add_yearly_k=0,
        pay_periods_k=26  # New schedule: Bi-weekly (26/yr) for K only
    )
]

# TAX RATES (Estimated decimals)
TAX_RATES = {
    'fed': 0.14,
    'soc_sec': 0.057,
    'medicare': 0.014,
    'state_ga': 0.05
}

# INSURANCE & DEDUCTIONS
# Note: These are PER PAYCHECK amounts.
# Logic assumes these are deducted from K's check (and thus subject to K's pay periods)
INSURANCE_COSTS = {
    'medical_per_paycheck': 240.27,
    'dental_per_paycheck': 13.24
}

RETIREMENT_RATES = {
    'd_403b_pct': 0.05,  # 5% of D's Gross
    'k_403b_pct': 0.05   # 5% of K's Gross
}

# MISSIONS / GIFTS (Fixed Monthly Amounts)
MISSIONS_SUPPORT = {
    'IDEAS': 200.00,
    'OM': 75.00,
    'CRU': 75.00
}

# ==========================================
# LOGIC & CALCULATIONS
# ==========================================

def calculate_monthly_finances(profile: IncomeProfile) -> Dict[str, float]:
    """
    Calculates the monthly gross, taxes, deductions, net pay, and tithe.
    Crucially, it separates D (24 periods) from K (variable periods).
    """
    try:
        # 1. Gross Income Calculation
        # Monthly averages are mathematically (Annual / 12) regardless of pay frequency,
        # but we track them to ensure totals are correct.
        total_salary_d = profile.salary_d + profile.add_yearly_d
        total_salary_k = profile.salary_k + profile.add_yearly_k
        
        yearly_gross = total_salary_d + total_salary_k
        monthly_gross = yearly_gross / MONTHS_PER_YEAR

        # 2. Tax Calculation
        # Taxes are applied to the total yearly gross
        fed_tax = yearly_gross * TAX_RATES['fed']
        soc_sec = yearly_gross * TAX_RATES['soc_sec']
        medicare = yearly_gross * TAX_RATES['medicare']
        state_tax = yearly_gross * TAX_RATES['state_ga']
        
        total_yearly_taxes = fed_tax + soc_sec + medicare + state_tax
        monthly_taxes = total_yearly_taxes / MONTHS_PER_YEAR

        # 3. Pre-Tax / Deduction Calculation
        
        # MEDICAL/DENTAL
        # Logic: Calculated based on K's specific pay periods (24 vs 26).
        # We assume insurance comes out of K's paycheck. 
        # If it came out of D's, we would use PAY_PERIODS_D_FIXED.
        total_insurance_per_check = INSURANCE_COSTS['medical_per_paycheck'] + INSURANCE_COSTS['dental_per_paycheck']
        monthly_medical_dental = (total_insurance_per_check * profile.pay_periods_k) / MONTHS_PER_YEAR

        # RETIREMENT (403b)
        # calculated individually to ensure D uses D's salary and K uses K's salary.
        # (Annual Salary / 12) * Rate gives the correct monthly average.
        
        # D's Retirement (Strictly based on D's salary, independent of K's pay periods)
        monthly_403b_d = (total_salary_d / MONTHS_PER_YEAR) * RETIREMENT_RATES['d_403b_pct']
        
        # K's Retirement (Based on K's salary)
        monthly_403b_k = (total_salary_k / MONTHS_PER_YEAR) * RETIREMENT_RATES['k_403b_pct']
        
        total_monthly_403b = monthly_403b_d + monthly_403b_k

        # 4. Net Pay Calculation
        monthly_net = monthly_gross - monthly_taxes - monthly_medical_dental - total_monthly_403b

        # 5. Tithe & Missions Calculation
        # Tithe is strictly 10% of Gross
        monthly_tithe = monthly_gross * 0.10
        
        # Missions sum
        monthly_missions = sum(MISSIONS_SUPPORT.values())

        return {
            'Yearly Gross': yearly_gross,
            'Monthly Gross': monthly_gross,
            'Monthly Taxes': monthly_taxes,
            'Monthly Health/Dental': monthly_medical_dental,
            'Monthly Retirement': total_monthly_403b,
            'Monthly Net Pay': monthly_net,
            'Monthly Tithe (10%)': monthly_tithe,
            'Monthly Missions': monthly_missions,
            'Net After Tithe & Missions': monthly_net - monthly_tithe - monthly_missions,
            'K Pay Periods': profile.pay_periods_k,
            'D Pay Periods': PAY_PERIODS_D_FIXED  # Explicitly shown for verification
        }

    except ZeroDivisionError:
        print("Error: Months per year cannot be zero.")
        return {}
    except Exception as e:
        print(f"An unexpected error occurred during calculation: {e}")
        return {}

def generate_report(scenario_list: List[IncomeProfile]):
    """
    Generates a comparative DataFrame and prints a summary for Monarch budgeting.
    """
    results = []

    for scen in scenario_list:
        metrics = calculate_monthly_finances(scen)
        if metrics:
            metrics['Scenario'] = scen.name
            results.append(metrics)
    
    # Create DataFrame for clean display
    df = pd.DataFrame(results)
    
    # Reorder columns to put Scenario first and Pay Period logic visible
    # This ensures we can visually verify D stayed at 24 and K moved to 26
    cols = ['Scenario', 'K Pay Periods', 'D Pay Periods'] + \
           [c for c in df.columns if c not in ['Scenario', 'K Pay Periods', 'D Pay Periods']]
    df = df[cols]
    
    # Transpose for easier reading (Categories as rows, Scenarios as columns)
    df_t = df.set_index('Scenario').T
    
    # Calculate Difference (New - Current) if exactly two scenarios exist
    if len(df.columns) >= 2:
        # We try to calculate difference, but ignore strings/non-numeric columns if they exist
        try:
             df_t['Difference'] = df_t.iloc[:, 1] - df_t.iloc[:, 0]
        except Exception:
            pass # Skip difference calculation for non-numeric fields

    # Display settings
    pd.options.display.float_format = '${:,.2f}'.format

    print("\n=======================================================")
    print("           EARNINGS ESTIMATE ANALYSIS")
    print("=======================================================")
    print(df_t)
    
    print("\n\n=======================================================")
    print("       MONARCH BUDGETING INPUTS (NEW SCENARIO)")
    print("=======================================================")
    
    # Extracting specific data for the "New" scenario for the user summary
    new_data = results[1] 
    
    print(f"For your Monarch Budget setup based on '{new_data['Scenario']}':")
    print(f"(Includes K @ {new_data['K Pay Periods']} periods/yr and D @ {new_data['D Pay Periods']} periods/yr)")
    print("-------------------------------------------------------")
    print(f"1. EXPECTED MONTHLY NET INCOME:   ${new_data['Monthly Net Pay']:,.2f}")
    print(f"   (This is the cash hitting the bank accounts)")
    print("")
    print(f"2. PLANNED GIVING (Breakdown):")
    print(f"   - Tithe (10% of Gross):        ${new_data['Monthly Tithe (10%)']:,.2f}")
    print(f"   - Missions (Fixed Gifts):      ${new_data['Monthly Missions']:,.2f}")
    print(f"   - TOTAL GIVING:                ${new_data['Monthly Tithe (10%)'] + new_data['Monthly Missions']:,.2f}")
    print("")
    print(f"3. TOTAL NET EARNINGS (Includes Tithe & Donations): ${new_data['Monthly Net Pay']:,.2f}")
    print(f"   (Use this amount for total inflows in Monarch)")
    print("-------------------------------------------------------")

if __name__ == "__main__":
    generate_report(scenarios)

# ---     20260101      WGRIFFITH2          --Script updated to strictly isolate D (24 periods) from K (26 periods) logic