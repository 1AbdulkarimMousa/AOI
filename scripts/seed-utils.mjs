export async function runCleanupSteps(steps) {
  const values = {};
  const errors = [];

  for (const step of steps) {
    try {
      values[step.name] = await step.run();
    } catch (error) {
      errors.push({ name: step.name, error });
    }
  }

  return { values, errors };
}
